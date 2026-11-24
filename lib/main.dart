import 'dart:convert';
import 'dart:io';
import 'package:offline_face_recognition/offline_face_recognition.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:mediapipe_retrieval/mediapipe_retrieval.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

void main() => runApp(const MaterialApp(
  debugShowCheckedModeBanner: false, home: Gallery(),
));

double cosine(List<double> a, List<double> b) {
  if (a.length != b.length || a.isEmpty) return -1;
  double dot = 0, aa = 0, bb = 0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i]*b[i]; aa += a[i]*a[i]; bb += b[i]*b[i];
  }
  return aa == 0 || bb == 0 ? -1 : dot / math.sqrt(aa*bb);
}

class Gallery extends StatefulWidget {
  const Gallery({super.key});
  @override State<Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<Gallery> {
  Database? db;
  UniversalEmbedder? model;
  OfflineFaceRecognition? faceEngine;
  final faceCandidates = <String, Set<String>>{};
  bool candidateMode = false;
  final query = TextEditingController();
  final assets = <String, AssetEntity>{};
  final rows = <String, Map<String, Object?>>{};
  final selected = <String>{};
  List<String> people = [];
  List<String> results = [];
  bool busy = false, stop = false, ready = false, ranked = false, missing = false;
  String status = '請授權相簿後掃描。';
  String personFilter = '';
  String placeFilter = '';

  @override void initState() { super.initState(); init(); }
  Future<void> init() async {
    try {
      db = await openDatabase(p.join(await getDatabasesPath(), 'pic_ai_v1.db'),
        version: 1, onCreate: (d, v) async {
          await d.execute('CREATE TABLE photos(id TEXT PRIMARY KEY, shot INTEGER, modified INTEGER, lat REAL, lon REAL, place TEXT DEFAULT "", vector TEXT)');
          await d.execute('CREATE TABLE people(name TEXT PRIMARY KEY)');
          await d.execute('CREATE TABLE tags(photo TEXT, person TEXT, PRIMARY KEY(photo,person))');
        });
      if (!mounted) return;
      setState(() {ready = true;});
      await scan(false);
    } catch(e) { if(mounted) setState(()=>status='初始化失敗：$e'); }
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
  Future<void> scan(bool ai) async {
    if (busy || db == null) return;
    setState(() {busy=true;stop=false;status='讀取相簿權限…';});
    int failures=0, embedded=0;
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) {
        assets.clear(); rows.clear(); results.clear(); selected.clear();
        throw StateError('未取得照片權限；請到設定開啟。');
      }
      assets.clear(); rows.clear(); results.clear(); selected.clear();
      for (int page=0; !stop; page++) {
        final batch = await PhotoManager.getAssetListPaged(page:page,pageCount:100,type:RequestType.image);
        if (batch.isEmpty) break;
        for (final a in batch) {
          if (stop) break;
          assets[a.id]=a;
          final old = await db!.query('photos',where:'id=?',whereArgs:[a.id]);
          final previous=old.isEmpty? <String,Object?>{} : old.first;
          final modified=a.modifiedDateTime.millisecondsSinceEpoch;
          final same=previous['modified']==modified;
          final loc=await a.latlngAsync();
          final gps=loc!=null && (loc.latitude!=0 || loc.longitude!=0);
          final row=<String,Object?>{
            'id':a.id, 'shot':a.createDateTime.millisecondsSinceEpoch,
            'modified':modified,'lat':gps?loc.latitude:null,'lon':gps?loc.longitude:null,
            'place':previous['place']??'', 'vector':same?previous['vector']:null
          };
          if(ai && row['vector']==null) {
            try {
              final e=await engine();
              final bytes=await a.thumbnailDataWithSize(const ThumbnailSize.square(512));
              if(bytes==null) throw StateError('無縮圖');
              final r=await e.embedImage(bytes);
              final vector=r.embeddings.first.floatEmbedding;
              if(vector==null || vector.isEmpty) throw StateError('無向量');
              row['vector']=jsonEncode(vector.toList());
              embedded++;
            } catch(_) {failures++;}
          }
          await db!.insert('photos',row,conflictAlgorithm:ConflictAlgorithm.replace);
          rows[a.id]=row;
        }
        if(mounted) setState(()=>status='已讀取 ${assets.length} 張；新增 AI 索引 $embedded 張，失敗 $failures 張');
        if(batch.length<100) break;
      }
      await refresh();
      if(mounted) setState(()=>status='掃描${stop?"已停止":"完成"}：${assets.length} 張；AI 索引 ${rows.values.where((r)=>r["vector"]!=null).length} 張，失敗 $failures 張。');
    } catch(e) {if(mounted)setState(()=>status='掃描失敗：$e');}
    finally {if(mounted)setState(()=>busy=false);}
  }

  Future<void> refresh({List<String>? order}) async {
    if(db==null)return;
    final names=await db!.query('people',orderBy:'name');
    final tags=await db!.query('tags',where:personFilter.isEmpty?null:'person=?',whereArgs:personFilter.isEmpty?null:[personFilter]);
    final ids=tags.map((t)=>t['photo'] as String).toSet();
    final base=order??assets.keys.toList();
    if(order==null)base.sort((a,b)=>(rows[b]?['shot'] as int? ?? 0).compareTo(rows[a]?['shot'] as int? ?? 0));
    if(!mounted)return;
    setState((){
      people=names.map((r)=>r['name'] as String).toList();
      results=base.where((id)=>assets.containsKey(id)
        && (personFilter.isEmpty||ids.contains(id))
        && (!missing||rows[id]?['lat']==null)
        && (placeFilter.isEmpty||(rows[id]?['place'] as String? ?? '').contains(placeFilter))).toList();
      selected.retainAll(results.toSet()); ranked=order!=null;
    });
  }

  Future<void> search() async {
    if(busy||query.text.trim().isEmpty)return;
    setState((){busy=true;status='載入本機模型並搜尋…';});
    try {
      final e=await engine();
      final v=(await e.embedText(query.text.trim())).embeddings.first.floatEmbedding;
      if(v==null)throw StateError('無文字向量');
      final scores=<String,double>{};
      for(final entry in rows.entries){
        final s=entry.value['vector'] as String?;
        if(s==null)continue;
        final x=(jsonDecode(s) as List).map((n)=>(n as num).toDouble()).toList();
        scores[entry.key]=cosine(v,x);
      }
      final order=scores.keys.toList()..sort((a,b)=>scores[b]!.compareTo(scores[a]!));
      await refresh(order:order);
      if(mounted)setState(()=>status='語意相似度排序：${results.length} 張（不是地點或人臉身分證明）');
    }catch(e){if(mounted)setState(()=>status='AI 搜尋失敗：$e');}
    finally{if(mounted)setState(()=>busy=false);}
  }

  Future<String?> ask(String title, [String initial='']) async {
    final c=TextEditingController(text:initial);
    final value=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(title),content:TextField(controller:c,autofocus:true),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('取消')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,c.text.trim()),child:const Text('儲存'))],
    ));
    c.dispose();return value;
  }
  Future<void> addPerson() async {
    final name=await ask('新增家人名稱（請先取得同意）');
    if(name==null||name.isEmpty)return;
    await db!.insert('people',{'name':name},conflictAlgorithm:ConflictAlgorithm.ignore);
    await refresh();
  }
  Future<void> tag() async {
    if(selected.isEmpty||people.isEmpty)return;
    final person=await showDialog<String>(context:context,builder:(ctx)=>SimpleDialog(
      title:const Text('將已選照片標記為家人（人工確認）'),
      children:people.map((x)=>SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,x),child:Text(x))).toList(),
    ));
    if(person==null)return;
    await db!.transaction((tx)async{
      for(final id in selected) {
        await tx.insert('tags',{'photo':id,'person':person},conflictAlgorithm:ConflictAlgorithm.ignore);
      }
    });
    selected.clear();await refresh();
  }
  Future<OfflineFaceRecognition> getFaceEngine() async {
    return faceEngine ??= await OfflineFaceRecognition.create();
  }
  Future<String?> choosePerson(String title) async {
    if(people.isEmpty) return null;
    return showDialog<String>(context:context,builder:(ctx)=>SimpleDialog(
      title:Text(title),
      children:people.map((name)=>SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,name),child:Text(name))).toList(),
    ));
  }
  Future<File> tempPhoto(AssetEntity a, Directory dir) async {
    final bytes=await a.thumbnailDataWithSize(const ThumbnailSize.square(1024));
    if(bytes==null) throw StateError('無法取得縮圖');
    return File('${dir.path}/photo.jpg').writeAsBytes(bytes,flush:true);
  }
  Future<void> enroll() async {
    if(busy || selected.isEmpty || people.isEmpty)return;
    final name=await choosePerson('選擇參考照片中的家人');
    if(name==null || !mounted)return;
    final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('確認參考照片'),
      content:const Text('請取得本人或監護人同意。每張選取照片只可包含該家人一張清楚正面臉孔，請勿選合照或其他人的照片。資料保留於本機。'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('取消')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('確認'))]));
    if(yes!=true)return;
    final ids=selected.toList();
    setState((){busy=true;status='建立家人參考資料…';});
    Directory? dir;
    var ok=0, failed=0;
    try {
      final local=await getFaceEngine();
      dir=await Directory.systemTemp.createTemp('pic_ai_reference_');
      for(final id in ids){
        try {
          final file=await tempPhoto(assets[id]!,dir);
          await local.register(image:file,id:'${name.length}:$name:$id',label:name);
          await db!.insert('tags',{'photo':id,'person':name},conflictAlgorithm:ConflictAlgorithm.ignore);
          ok++;
        } catch(_){failed++;}
      }
      selected.clear();faceCandidates.clear();candidateMode=false;
      await refresh();
      if(mounted)setState(()=>status='已登錄 $ok 張參考照片，失敗 $failed 張。');
    } catch(e){if(mounted)setState(()=>status='參考資料建立失敗：$e');}
    finally{try{await dir?.delete(recursive:true);}finally{if(mounted)setState(()=>busy=false);}}
  }
  Future<void> findFamily() async {
    if(busy || assets.isEmpty || people.isEmpty)return;
    final name=await choosePerson('尋找哪位家人的候選照片？');
    if(name==null)return;
    setState((){busy=true;stop=false;status='正在本機搜尋人物候選…';});
    Directory? dir;
    var done=0, failed=0;
    final matches=<String>[];
    try {
      final local=await getFaceEngine();
      final templates=await local.listTemplates();
      if(templates.isEmpty)throw StateError('請先登錄家人參考照片');
      dir=await Directory.systemTemp.createTemp('pic_ai_scan_');
      faceCandidates.clear();
      for(final a in assets.values){
        if(stop)break;
        try{
          final file=await tempPhoto(a,dir);
          final found=await local.recognizeMultiple(image:file,limit:10);
          final labels=<String>{};
          for(final r in found){
            final label=r.template?.label;
            if(r.isMatch && label!=null && people.contains(label))labels.add(label);
          }
          if(labels.isNotEmpty)faceCandidates[a.id]=labels;
          if(labels.contains(name))matches.add(a.id);
        }catch(_){failed++;}
        done++;
        if(mounted && done%10==0)setState(()=>status='已比對 $done/${assets.length} 張；候選 ${matches.length} 張');
      }
      personFilter='';missing=false;placeFilter='';
      candidateMode=true;
      await refresh(order:matches);
      if(mounted)setState(()=>status='候選 ${matches.length} 張；已比對 $done 張、失敗 $failed 張。請人工確認後才標記。');
    }catch(e){if(mounted)setState(()=>status='人臉搜尋失敗：$e');}
    finally{try{await dir?.delete(recursive:true);}finally{if(mounted)setState(()=>busy=false);}}
  }
  Future<void> batchPlace() async {
    if(selected.isEmpty)return;
    final name=await ask('將已選照片標記為同一人工確認地點');
    if(name==null||name.isEmpty)return;
    final ids=selected.toList();
    await db!.transaction((tx)async{
      for(final id in ids){
        await tx.update('photos',{'place':name},where:'id=?',whereArgs:[id]);
      }
    });
    for(final id in ids){rows[id]={...rows[id]!, 'place':name};}
    selected.clear();await refresh();
  }
  Future<void> detail(String id) async {
    final r=rows[id]!;
    final shot=r['shot'] as int;
    final near=rows.values.where((x)=>x['id']!=id&&x['lat']!=null
      && ((x['shot'] as int)-shot).abs()<=30*60*1000).toList()
      ..sort((a,b)=>((a['shot'] as int)-shot).abs().compareTo(((b['shot'] as int)-shot).abs()));
    final tags=await db!.query('tags',where:'photo=?',whereArgs:[id]);
    if(!mounted)return;
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('照片與地點線索'),content:SizedBox(width:360,child:SingleChildScrollView(child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
          Thumb(asset:assets[id]!,size:700),
          Text('拍攝：${DateTime.fromMillisecondsSinceEpoch(shot)}'),
          Text('原始 GPS：${r["lat"]==null?"無或無法讀取":"${r["lat"]}, ${r["lon"]}"}'),
          Text('人工確認地點：${r["place"]}'),
          Text('人工家人標籤：${tags.map((t)=>t["person"]).join("、")}'),
          if(r['lat']==null) ...[
            const Text('前後 30 分鐘有 GPS 的照片（僅供推測，非原始定位）'),
            if(near.isEmpty)const Text('未找到時間線索'),
            for(final x in near.take(5)) ListTile(
              leading:SizedBox(width:50,height:50,child:Thumb(asset:assets[x['id']]!,size:120)),
              title:Text('${x["lat"]}, ${x["lon"]}'),
              subtitle:Text('相隔 ${((x["shot"] as int)-shot).abs()~/60000} 分鐘'),
            )
          ]
        ]))),actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('關閉')),
          TextButton(onPressed:()async{
            Navigator.pop(ctx);
            final name=await ask('人工確認地點（不改原照片）',r['place'] as String? ?? '');
            if(name==null)return;
            await db!.update('photos',{'place':name},where:'id=?',whereArgs:[id]);
            rows[id]={...r,'place':name};await refresh();
          },child:const Text('編輯地點'))
        ],
    ));
  }
  Future<void> clearLocal() async {
    final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('清除所有本機索引與標籤？'),content:const Text('不刪除原始照片。'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('取消')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('清除'))]));
    if(yes!=true)return;
    try { await (await getFaceEngine()).clear(); } catch(e) {if(mounted)setState(()=>status='無法清除人臉參考資料：$e');return;}
    faceCandidates.clear();candidateMode=false;
    await db!.transaction((tx)async{for(final t in ['tags','people','photos']){await tx.delete(t);}});
    assets.clear();rows.clear();results.clear();people.clear();selected.clear();personFilter='';placeFilter='';missing=false;
    if(mounted)setState(()=>status='本機資料已清除。');
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('PIC_AI 私人相簿'),actions:[
      IconButton(onPressed:ready&&!busy?clearLocal:null,icon:const Icon(Icons.delete_sweep_outlined),tooltip:'清除本機索引'),
    ]),
    body:SafeArea(child:Column(children:[
      Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(status),if(busy)const LinearProgressIndicator(),
        Wrap(spacing:8,children:[
          OutlinedButton(onPressed:ready&&!busy?()=>scan(false):null,child:const Text('讀取照片')),
          FilledButton(onPressed:ready&&!busy?()=>scan(true):null,child:const Text('建立 AI 索引')),
          if(busy)TextButton(onPressed:()=>stop=true,child:const Text('停止掃描')),
          TextButton(onPressed:ready&&!busy?addPerson:null,child:const Text('新增家人')),
          TextButton(onPressed:!busy&&selected.isNotEmpty&&people.isNotEmpty?tag:null,child:Text('標記已選 ${selected.length} 張')),
          OutlinedButton(onPressed:!busy&&selected.isNotEmpty&&people.isNotEmpty?enroll:null,child:const Text('登錄參考人臉')),
          FilledButton(onPressed:!busy&&people.isNotEmpty&&assets.isNotEmpty?findFamily:null,child:const Text('找家人候選')),
          TextButton(onPressed:!busy&&selected.isNotEmpty?batchPlace:null,child:const Text('整批設定地點')),
        ]),
        TextField(controller:query,enabled:!busy,decoration:InputDecoration(
          hintText:'例如：日本寺廟、海邊、生日蛋糕',
          suffixIcon:IconButton(onPressed:!busy?search:null,icon:const Icon(Icons.search)))),
        Wrap(spacing:8,children:[
          DropdownButton<String>(value:personFilter,items:['',...people].map((n)=>DropdownMenuItem(value:n,child:Text(n.isEmpty?'所有家人':n))).toList(),
            onChanged:busy?null:(n){personFilter=n??'';refresh();}),
          FilterChip(label:const Text('缺少 GPS'),selected:missing,onSelected:busy?null:(v){missing=v;refresh();}),
          TextButton(onPressed:busy?null:()async{final n=await ask('搜尋人工確認地點',placeFilter);if(n!=null){placeFilter=n;await refresh();}},child:Text(placeFilter.isEmpty?'地點篩選':placeFilter)),
          if(ranked)TextButton(onPressed:busy?null:()=>refresh(),child:const Text('取消語意排序'))
        ]),
        Text(candidateMode?'目前為人臉候選搜尋；請核對後再選取標記。':'家人標籤為人工確認；長按照片可查看地點線索。',style:const TextStyle(fontSize:12)),
      ])),
      Expanded(child:GridView.builder(gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:3,crossAxisSpacing:2,mainAxisSpacing:2),
        itemCount:results.length,itemBuilder:(context,i){
          final id=results[i];
          return GestureDetector(onTap:busy?null:()=>setState((){if(!selected.add(id))selected.remove(id);}),
            onLongPress:busy?null:()=>detail(id),
            child:Stack(fit:StackFit.expand,children:[
              Thumb(key:ValueKey(id),asset:assets[id]!,size:240),
              if(selected.contains(id))const Align(alignment:Alignment.topRight,child:Icon(Icons.check_circle,color:Colors.green)),
              if(rows[id]?['lat']==null)const Align(alignment:Alignment.bottomLeft,child:Icon(Icons.location_off,color:Colors.orange)),
            ]));
        })),
    ])),
  );
  @override void dispose(){query.dispose(); model?.dispose();faceEngine?.dispose();db?.close();super.dispose();}
}

class Thumb extends StatefulWidget {
  final AssetEntity asset; final int size;
  const Thumb({super.key,required this.asset,required this.size});
  @override State<Thumb> createState()=>_ThumbState();
}
class _ThumbState extends State<Thumb>{
  late Future<Uint8List?> bytes;
  @override void initState(){super.initState();bytes=widget.asset.thumbnailDataWithSize(ThumbnailSize.square(widget.size));}
  @override Widget build(BuildContext context)=>FutureBuilder<Uint8List?>(future:bytes,builder:(ctx,s)=>
    s.data==null?const Center(child:Icon(Icons.photo_outlined)):Image.memory(s.data!,fit:BoxFit.cover));
}
