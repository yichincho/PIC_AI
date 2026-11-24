import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:mediapipe_retrieval/mediapipe_retrieval.dart';
import 'package:offline_face_recognition/offline_face_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:sqflite/sqflite.dart';
import 'face_crop.dart';
import 'face_quality.dart';

/// 已是中文、可直接顯示給使用者的錯誤。
class AppError implements Exception {
  final String message;
  AppError(this.message);
  @override String toString() => message;
}

/// 將例外轉成友善的中文訊息；不顯示 "Bad state:" 等原始字串。
String friendlyError(Object e) {
  if (e is AppError) return e.message;
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('HandshakeException') ||
      s.contains('ClientException') || s.contains('Failed host lookup')) {
    return '網路連線失敗。下載 AI 模型需要網路，請連線後再試一次。';
  }
  if (s.contains('FileSystemException')) return '檔案讀寫失敗，請確認手機儲存空間足夠後再試。';
  if (s.contains('DatabaseException')) return '本機資料庫發生問題，請重新開啟 App 後再試。';
  return '發生未預期的問題，請稍後再試一次。';
}

class FaceCheckEntry {
  final Map<String, Object?> ref;
  final double mean;
  final bool flagged;
  FaceCheckEntry(this.ref, this.mean, this.flagged);
}

class FaceCheckReport {
  final List<FaceCheckEntry> entries;
  final int unreadable;
  FaceCheckReport(this.entries, this.unreadable);
}

const _faceRefsSql = 'CREATE TABLE IF NOT EXISTS face_refs('
    'id TEXT PRIMARY KEY, person TEXT NOT NULL, photo TEXT, crop_path TEXT, created INTEGER)';

class AppState extends ChangeNotifier {
  Database? db;
  UniversalEmbedder? model;
  OfflineFaceRecognition? faceEngine;
  final faceCandidates = <String, Set<String>>{};
  final candidates = <String, List<String>>{};
  bool candidateMode = false;
  final assets = <String, AssetEntity>{};
  final rows = <String, Map<String, Object?>>{};
  final selected = <String>{};
  List<String> people = [];
  List<String> results = [];
  Map<String, int> refCounts = {};
  bool busy = false, stop = false, stoppable = false, ready = false, ranked = false, missing = false;
  bool statusIsError = false;
  int photoCount = 0;
  double? progress;
  String status = '';
  String personFilter = '';
  String placeFilter = '';
  bool _disposed = false;
  bool _legacyChecked = false;

  bool get showOnboarding => ready && photoCount == 0 && assets.isEmpty && !busy;

  @override void notifyListeners() { if (!_disposed) super.notifyListeners(); }
  void setStatus(String s, {bool error = false}) { status = s; statusIsError = error; notifyListeners(); }
  void _begin(String s, {bool canStop = false}) {
    busy = true; stop = false; stoppable = canStop; progress = null; setStatus(s);
  }
  void _end() { busy = false; stoppable = false; progress = null; notifyListeners(); }
  void requestStop() { stop = true; notifyListeners(); }

  Future<void> init() async {
    try {
      db = await openDatabase(p.join(await getDatabasesPath(), 'pic_ai_v1.db'),
        version: 3,
        onCreate: (d, v) async {
          await d.execute('CREATE TABLE app_meta(key TEXT PRIMARY KEY, value TEXT)');
          await d.execute('CREATE TABLE photos(id TEXT PRIMARY KEY, shot INTEGER, modified INTEGER, lat REAL, lon REAL, place TEXT DEFAULT "", vector TEXT)');
          await d.execute('CREATE TABLE people(name TEXT PRIMARY KEY)');
          await d.execute('CREATE TABLE tags(photo TEXT, person TEXT, PRIMARY KEY(photo,person))');
          await d.execute(_faceRefsSql);
        },
        onUpgrade: (d, old, next) async {
          if (old < 2) await d.execute('CREATE TABLE IF NOT EXISTS app_meta(key TEXT PRIMARY KEY, value TEXT)');
          if (old < 3) await d.execute(_faceRefsSql);
        },
        onOpen: (d) async { await d.execute(_faceRefsSql); },
      );
      photoCount = Sqflite.firstIntValue(await db!.rawQuery('SELECT COUNT(*) FROM photos')) ?? 0;
      ready = true;
      notifyListeners();
      await refresh();
      if (photoCount > 0) await scan(false);
    } catch (e) {
      setStatus('初始化失敗：${friendlyError(e)}', error: true);
    }
  }

  Future<UniversalEmbedder> engine() async {
    if (model != null) return model!;
    ModelStore.allowDownloads = true;
    final caps = await queryUniversalEmbedderCapabilities();
    model = await UniversalEmbedder.create(UniversalEmbedderOptions(
      model: RetrievalModels.embeddingGemma2TextVision,
      delegate: caps.supportedDelegates.first,
    ));
    return model!;
  }

  Future<OfflineFaceRecognition> getFaceEngine() async {
    return faceEngine ??= await OfflineFaceRecognition.create();
  }

  Future<Directory> _facesDir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'faces'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  String _safeName(String id) => base64Url.encode(utf8.encode(id)).replaceAll('=', '');

  Future<void> scan(bool ai) async {
    if (busy || db == null) return;
    _begin('讀取相簿權限…', canStop: true);
    int failures = 0, embedded = 0;
    try {
      final permission = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(
          androidPermission: AndroidPermission(type: RequestType.image, mediaLocation: true),
        ),
      );
      if (!permission.hasAccess) {
        assets.clear(); rows.clear(); results.clear(); selected.clear();
        await PhotoManager.openSetting();
        throw AppError('未取得照片權限（狀態：${permission.name}）。已開啟設定頁，請允許「儲存空間／照片」後再按一次。');
      }
      assets.clear(); rows.clear(); results.clear(); selected.clear();
      for (int page = 0; !stop; page++) {
        final batch = await PhotoManager.getAssetListPaged(page: page, pageCount: 100, type: RequestType.image);
        if (batch.isEmpty) break;
        for (final a in batch) {
          if (stop) break;
          assets[a.id] = a;
          final old = await db!.query('photos', where: 'id=?', whereArgs: [a.id]);
          final previous = old.isEmpty ? <String, Object?>{} : old.first;
          final modified = a.modifiedDateTime.millisecondsSinceEpoch;
          final same = previous['modified'] == modified;
          final loc = await a.latlngAsync();
          final gps = loc != null && (loc.latitude != 0 || loc.longitude != 0);
          final row = <String, Object?>{
            'id': a.id, 'shot': a.createDateTime.millisecondsSinceEpoch,
            'modified': modified, 'lat': gps ? loc.latitude : null, 'lon': gps ? loc.longitude : null,
            'place': previous['place'] ?? '', 'vector': same ? previous['vector'] : null
          };
          if (ai && row['vector'] == null) {
            try {
              final e = await engine();
              final bytes = await a.thumbnailDataWithSize(const ThumbnailSize.square(512));
              if (bytes == null) throw AppError('無縮圖');
              final r = await e.embedImage(bytes);
              final vector = r.embeddings.first.floatEmbedding;
              if (vector == null || vector.isEmpty) throw AppError('無向量');
              row['vector'] = jsonEncode(vector.toList());
              embedded++;
            } catch (_) { failures++; }
          }
          await db!.insert('photos', row, conflictAlgorithm: ConflictAlgorithm.replace);
          rows[a.id] = row;
        }
        setStatus('已讀取 ${assets.length} 張；新增 AI 索引 $embedded 張，失敗 $failures 張');
        if (batch.length < 100) break;
      }
      photoCount = Sqflite.firstIntValue(await db!.rawQuery('SELECT COUNT(*) FROM photos')) ?? 0;
      await refresh();
      final indexed = rows.values.where((r) => r['vector'] != null).length;
      setStatus('掃描${stop ? "已停止" : "完成"}：${assets.length} 張；AI 索引 $indexed 張，失敗 $failures 張。');
    } catch (e) {
      setStatus('掃描失敗：${friendlyError(e)}', error: true);
    } finally { _end(); }
  }

  Future<void> refresh({List<String>? order}) async {
    if (db == null) return;
    final names = await db!.query('people', orderBy: 'name');
    final tags = await db!.query('tags',
        where: personFilter.isEmpty ? null : 'person=?',
        whereArgs: personFilter.isEmpty ? null : [personFilter]);
    final ids = tags.map((t) => t['photo'] as String).toSet();
    final base = order ?? assets.keys.toList();
    if (order == null) {
      base.sort((a, b) => (rows[b]?['shot'] as int? ?? 0).compareTo(rows[a]?['shot'] as int? ?? 0));
    }
    people = names.map((r) => r['name'] as String).toList();
    results = base.where((id) => assets.containsKey(id)
        && (personFilter.isEmpty || ids.contains(id))
        && (!missing || rows[id]?['lat'] == null)
        && (placeFilter.isEmpty || (rows[id]?['place'] as String? ?? '').contains(placeFilter))).toList();
    selected.retainAll(results.toSet());
    ranked = order != null;
    notifyListeners();
    unawaited(refreshRefCounts());
  }

  /// 參考臉數量：以 face_refs 為準；舊版（沒有 face_refs 列）的模板以人臉引擎內同標籤數量補足。
  Future<void> refreshRefCounts() async {
    if (db == null) return;
    final counts = <String, int>{};
    for (final r in await db!.rawQuery('SELECT person, COUNT(*) AS c FROM face_refs GROUP BY person')) {
      counts[r['person'] as String] = (r['c'] as num).toInt();
    }
    if (!_legacyChecked && people.any((n) => (counts[n] ?? 0) == 0)) {
      _legacyChecked = true;
      try {
        final templates = await (await getFaceEngine()).listTemplates();
        for (final n in people) {
          final c = templates.where((t) => t.label == n).length;
          if (c > (counts[n] ?? 0)) counts[n] = c;
        }
      } catch (_) {}
    } else {
      for (final n in people) { counts[n] = counts[n] ?? 0; }
    }
    refCounts = {for (final n in people) n: counts[n] ?? 0};
    notifyListeners();
  }

  Future<void> search(String text) async {
    final q = text.trim();
    if (busy || q.isEmpty) return;
    _begin('載入本機模型並搜尋…');
    try {
      final e = await engine();
      final v = (await e.embedText(q)).embeddings.first.floatEmbedding;
      if (v == null) throw AppError('無文字向量');
      final scores = <String, double>{};
      for (final entry in rows.entries) {
        final s = entry.value['vector'] as String?;
        if (s == null) continue;
        final x = (jsonDecode(s) as List).map((n) => (n as num).toDouble()).toList();
        scores[entry.key] = cosine(v, x);
      }
      final order = scores.keys.toList()..sort((a, b) => scores[b]!.compareTo(scores[a]!));
      await refresh(order: order);
      setStatus('語意相似度排序：${results.length} 張（不是地點或人臉身分證明）');
    } catch (e) {
      setStatus('AI 搜尋失敗：${friendlyError(e)}', error: true);
    } finally { _end(); }
  }

  Future<void> clearRanking() async { candidateMode = false; await refresh(); }
  Future<void> setPersonFilter(String n) async { personFilter = n; await refresh(); }
  Future<void> setMissing(bool v) async { missing = v; await refresh(); }
  Future<void> setPlaceFilter(String n) async { placeFilter = n; await refresh(); }
  void toggleSelect(String id) {
    if (!selected.add(id)) selected.remove(id);
    notifyListeners();
  }
  void clearSelection() { selected.clear(); notifyListeners(); }

  Future<void> addPerson(String name) async {
    if (db == null || name.isEmpty) return;
    await db!.insert('people', {'name': name}, conflictAlgorithm: ConflictAlgorithm.ignore);
    await refresh();
  }

  Future<void> tagSelected(String person) async {
    if (selected.isEmpty || db == null) return;
    await db!.transaction((tx) async {
      for (final id in selected) {
        await tx.insert('tags', {'photo': id, 'person': person}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    selected.clear();
    await refresh(order: ranked ? results : null);
  }

  Future<void> placeSelected(String name) async {
    if (selected.isEmpty || db == null || name.isEmpty) return;
    final ids = selected.toList();
    await db!.transaction((tx) async {
      for (final id in ids) {
        await tx.update('photos', {'place': name}, where: 'id=?', whereArgs: [id]);
      }
    });
    for (final id in ids) { rows[id] = {...rows[id]!, 'place': name}; }
    selected.clear();
    await refresh(order: ranked ? results : null);
  }

  Future<void> setPlace(String id, String name) async {
    await db!.update('photos', {'place': name}, where: 'id=?', whereArgs: [id]);
    rows[id] = {...rows[id]!, 'place': name};
    await refresh(order: ranked ? results : null);
  }

  Future<File> tempPhoto(AssetEntity a, Directory dir) async {
    final bytes = await a.thumbnailDataWithSize(const ThumbnailSize.square(1024));
    if (bytes == null) throw AppError('無法取得縮圖');
    return File('${dir.path}/photo.jpg').writeAsBytes(bytes, flush: true);
  }

  /// 登錄參考臉。多張臉時呼叫 [pickFace]：回傳索引；-1 略過此張；-2 取消全部。
  Future<void> enrollFaces(String name, List<String> ids,
      Future<int> Function(List<Uint8List> crops) pickFace) async {
    if (busy || db == null || ids.isEmpty) return;
    _begin('建立家人參考資料…', canStop: true);
    Directory? dir;
    FaceDetector? detector;
    var ok = 0, failed = 0, skipped = 0;
    try {
      final local = await getFaceEngine();
      final tmp = await Directory.systemTemp.createTemp('pic_ai_reference_');
      dir = tmp;
      final faces = await _facesDir();
      final det = FaceDetector(options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate, minFaceSize: 0.05));
      detector = det;
      for (var i = 0; i < ids.length; i++) {
        if (stop) break;
        final id = ids[i];
        progress = i / ids.length;
        setStatus('處理第 ${i + 1}/${ids.length} 張…');
        try {
          final asset = assets[id];
          if (asset == null) throw AppError('找不到照片');
          final bytes = await asset.thumbnailDataWithSize(const ThumbnailSize.square(1024));
          if (bytes == null) throw AppError('無法取得縮圖');
          final photo = await File('${tmp.path}/photo.jpg').writeAsBytes(bytes, flush: true);
          final found = await det.processImage(InputImage.fromFilePath(photo.path));
          if (found.isEmpty) { failed++; continue; }
          final boxes = <FaceBox>[for (final f in found)
            (left: f.boundingBox.left, top: f.boundingBox.top,
             width: f.boundingBox.width, height: f.boundingBox.height)];
          final crops = cropFaces(bytes, boxes);
          var index = 0;
          if (crops.length > 1) {
            final pick = await pickFace(crops);
            if (pick == -2) break;
            if (pick < 0) { skipped++; continue; }
            index = pick;
          }
          final templateId = '${name.length}:$name:$id:f$index';
          final cropFile = await File('${tmp.path}/face_$index.jpg').writeAsBytes(crops[index], flush: true);
          await local.register(image: cropFile, id: templateId, label: name);
          final saved = File(p.join(faces.path, '${_safeName(templateId)}.jpg'));
          await saved.writeAsBytes(crops[index], flush: true);
          await db!.insert('face_refs', {
            'id': templateId, 'person': name, 'photo': id,
            'crop_path': saved.path, 'created': DateTime.now().millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          await db!.insert('tags', {'photo': id, 'person': name}, conflictAlgorithm: ConflictAlgorithm.ignore);
          ok++;
        } catch (_) { failed++; }
      }
      selected.clear(); faceCandidates.clear(); candidateMode = false;
      await refresh();
      setStatus('已加入 $ok 張參考臉，略過 $skipped 張，失敗 $failed 張（含找不到臉）。');
    } catch (e) {
      setStatus('參考資料建立失敗：${friendlyError(e)}', error: true);
    } finally {
      try { await detector?.close(); await dir?.delete(recursive: true); } finally { _end(); }
    }
  }

  Future<void> findFamily(String name) async {
    if (busy || assets.isEmpty || people.isEmpty) return;
    _begin('正在本機搜尋人物候選…', canStop: true);
    Directory? dir;
    var done = 0, failed = 0;
    final matches = <String>[];
    try {
      final local = await getFaceEngine();
      final templates = await local.listTemplates();
      if (templates.isEmpty) throw AppError('請先加入家人參考臉。');
      dir = await Directory.systemTemp.createTemp('pic_ai_scan_');
      faceCandidates.clear();
      for (final a in assets.values) {
        if (stop) break;
        try {
          final file = await tempPhoto(a, dir);
          final found = await local.recognizeMultiple(image: file, limit: 10);
          final labels = <String>{};
          for (final r in found) {
            final label = r.template?.label;
            if (r.isMatch && label != null && people.contains(label)) labels.add(label);
          }
          if (labels.isNotEmpty) faceCandidates[a.id] = labels;
          if (labels.contains(name)) matches.add(a.id);
        } catch (_) { failed++; }
        done++;
        if (done % 10 == 0) {
          progress = done / assets.length;
          setStatus('已比對 $done/${assets.length} 張；候選 ${matches.length} 張');
        }
      }
      candidates[name] = matches;
      personFilter = ''; missing = false; placeFilter = '';
      candidateMode = true;
      await refresh(order: matches);
      setStatus('候選 ${matches.length} 張；已比對 $done 張、失敗 $failed 張。請到「確認候選」人工確認後才標記。');
    } catch (e) {
      setStatus('人臉搜尋失敗：${friendlyError(e)}', error: true);
    } finally {
      try { await dir?.delete(recursive: true); } finally { _end(); }
    }
  }

  Future<Set<String>> taggedPhotos(String person) async {
    final t = await db!.query('tags', where: 'person=?', whereArgs: [person]);
    return t.map((r) => r['photo'] as String).toSet();
  }

  Future<void> confirmCandidate(String person, String photo) async {
    await db!.insert('tags', {'photo': photo, 'person': person}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, Object?>>> faceRefsFor(String person) async {
    return db!.query('face_refs', where: 'person=?', whereArgs: [person], orderBy: 'created');
  }

  Future<void> deleteRef(Map<String, Object?> ref) async {
    final id = ref['id'] as String;
    try { await (await getFaceEngine()).deleteTemplate(id); } catch (_) {}
    final path = ref['crop_path'] as String?;
    if (path != null) {
      try { final f = File(path); if (await f.exists()) await f.delete(); } catch (_) {}
    }
    await db!.delete('face_refs', where: 'id=?', whereArgs: [id]);
    await refreshRefCounts();
  }

  /// 參考檢查（不是身分驗證）：比較同一人所有參考臉之間的相似度。
  Future<FaceCheckReport> selfCheck(String person) async {
    final refs = await faceRefsFor(person);
    final local = await getFaceEngine();
    final used = <Map<String, Object?>>[];
    final embeddings = <List<double>>[];
    var unreadable = 0;
    for (final r in refs) {
      final path = r['crop_path'] as String?;
      if (path == null || !File(path).existsSync()) { unreadable++; continue; }
      try {
        final res = await local.recognize(image: File(path));
        if (res.embedding.isEmpty) { unreadable++; continue; }
        embeddings.add(res.embedding);
        used.add(r);
      } catch (_) { unreadable++; }
    }
    if (embeddings.length < minRefFaces) throw AppError('至少 $minRefFaces 張才能自我檢查');
    final check = checkFaceConsistency(embeddings);
    return FaceCheckReport([
      for (var i = 0; i < used.length; i++) FaceCheckEntry(used[i], check.means[i], check.flagged[i]),
    ], unreadable);
  }

  Future<void> clearLocal() async {
    if (db == null) return;
    try {
      await (await getFaceEngine()).clear();
    } catch (e) {
      setStatus('無法清除人臉參考資料：${friendlyError(e)}', error: true);
      return;
    }
    faceCandidates.clear(); candidates.clear(); candidateMode = false;
    await db!.transaction((tx) async {
      for (final t in ['tags', 'people', 'photos', 'face_refs']) { await tx.delete(t); }
    });
    try {
      final d = await _facesDir();
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
    assets.clear(); rows.clear(); results.clear(); people = []; refCounts = {};
    selected.clear(); personFilter = ''; placeFilter = ''; missing = false; ranked = false;
    photoCount = 0; _legacyChecked = false;
    setStatus('本機資料已清除。');
  }

  @override void dispose() {
    _disposed = true;
    model?.dispose(); faceEngine?.dispose(); db?.close();
    super.dispose();
  }
}
