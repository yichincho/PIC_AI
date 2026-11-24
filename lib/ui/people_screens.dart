import 'dart:io';
import 'package:flutter/material.dart';
import '../app_state.dart';
import 'common.dart';

/// 挑選含有該家人的照片（多選），回傳照片 id 清單。
class PhotoPickerScreen extends StatefulWidget {
  final AppState state; final String name;
  const PhotoPickerScreen({super.key, required this.state, required this.name});
  @override State<PhotoPickerScreen> createState() => _PhotoPickerScreenState();
}
class _PhotoPickerScreenState extends State<PhotoPickerScreen> {
  final picked = <String>{};
  late final List<String> ids;
  @override void initState() {
    super.initState();
    final s = widget.state;
    ids = s.assets.keys.toList()
      ..sort((a, b) => (s.rows[b]?['shot'] as int? ?? 0).compareTo(s.rows[a]?['shot'] as int? ?? 0));
  }
  @override Widget build(BuildContext context) {
    final s = widget.state;
    return Scaffold(
      appBar: AppBar(title: Text('選擇有「${widget.name}」的照片')),
      body: ids.isEmpty
        ? const Center(child: Padding(padding: EdgeInsets.all(kPad),
            child: Text('還沒有照片。請先到「設定」分頁讀取照片。', style: TextStyle(fontSize: 15))))
        : Column(children: [
            const Padding(padding: EdgeInsets.all(kPad), child: Text(
              '建議選不同角度、不同時期的清楚正面照；合照可以，下一步會讓你點選是哪一張臉。',
              style: TextStyle(fontSize: 14))),
            Expanded(child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
              itemCount: ids.length,
              itemBuilder: (context, i) {
                final id = ids[i];
                return GestureDetector(
                  onTap: () => setState(() { if (!picked.add(id)) picked.remove(id); }),
                  child: Stack(fit: StackFit.expand, children: [
                    PhotoThumb(key: ValueKey(id), asset: s.assets[id]!, size: 240),
                    if (picked.contains(id)) const Align(alignment: Alignment.topRight,
                      child: Padding(padding: EdgeInsets.all(2), child: Icon(Icons.check_circle, color: Colors.green))),
                  ]));
              })),
            SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(kPad),
              child: SizedBox(width: double.infinity, child: FilledButton(
                onPressed: picked.isEmpty ? null : () => Navigator.pop(context, picked.toList()),
                child: Text('下一步（已選 ${picked.length} 張）'))))),
          ]),
    );
  }
}

/// 逐張確認候選：是 → 寫入人工標籤。
class CandidateReviewScreen extends StatefulWidget {
  final AppState state; final String name;
  const CandidateReviewScreen({super.key, required this.state, required this.name});
  @override State<CandidateReviewScreen> createState() => _CandidateReviewScreenState();
}
class _CandidateReviewScreenState extends State<CandidateReviewScreen> {
  List<String>? pending;
  int reviewed = 0, confirmed = 0;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    final s = widget.state;
    final tagged = await s.taggedPhotos(widget.name);
    final list = [for (final id in s.candidates[widget.name] ?? <String>[])
      if (!tagged.contains(id) && s.assets.containsKey(id)) id];
    if (mounted) setState(() => pending = list);
  }
  Future<void> answer(bool yes) async {
    final list = pending;
    if (list == null || list.isEmpty) return;
    final id = list.first;
    if (yes) { await widget.state.confirmCandidate(widget.name, id); confirmed++; }
    reviewed++;
    if (mounted) setState(() => list.removeAt(0));
  }
  Future<void> confirmRest() async {
    final list = pending;
    if (list == null || list.isEmpty) return;
    final yes = await confirmDialog(context, '全部確認剩下的？',
      '會把剩下 ${list.length} 張都標記為「${widget.name}」。人臉比對只是候選，請確定你已大致看過。',
      confirm: '全部確認');
    if (!yes) return;
    for (final id in List<String>.of(list)) {
      await widget.state.confirmCandidate(widget.name, id);
      confirmed++; reviewed++;
    }
    if (mounted) setState(() => list.clear());
  }
  @override Widget build(BuildContext context) {
    final s = widget.state;
    final list = pending;
    Widget body;
    if (list == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (list.isEmpty) {
      body = Center(child: Padding(padding: const EdgeInsets.all(kPad), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_outline, size: 48),
          const SizedBox(height: 12),
          Text('已檢視 $reviewed 張，確認 $confirmed 張。沒有待確認的候選了。',
            style: const TextStyle(fontSize: 15), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('完成')),
        ])));
    } else {
      body = Column(children: [
        Padding(padding: const EdgeInsets.all(kPad), child: Text(
          '已檢視 $reviewed 張，剩 ${list.length} 張。這張照片裡有「${widget.name}」嗎？',
          style: const TextStyle(fontSize: 15))),
        Expanded(child: Container(color: Colors.black12, width: double.infinity,
          child: PhotoThumb(key: ValueKey(list.first), asset: s.assets[list.first]!, size: 1024, fit: BoxFit.contain))),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(kPad), child: Column(children: [
          Row(children: [
            Expanded(child: FilledButton(onPressed: () => answer(true), child: const Text('是'))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton(onPressed: () => answer(false), child: const Text('不是'))),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TextButton(onPressed: confirmRest, child: const Text('全部確認剩下的')),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('結束')),
          ]),
        ]))),
      ]);
    }
    return Scaffold(appBar: AppBar(title: Text('確認「${widget.name}」的候選')), body: body);
  }
}

/// 查看與刪除參考臉。
class ReferenceFacesScreen extends StatefulWidget {
  final AppState state; final String name;
  const ReferenceFacesScreen({super.key, required this.state, required this.name});
  @override State<ReferenceFacesScreen> createState() => _ReferenceFacesScreenState();
}
class _ReferenceFacesScreenState extends State<ReferenceFacesScreen> {
  List<Map<String, Object?>>? refs;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    final r = await widget.state.faceRefsFor(widget.name);
    if (mounted) setState(() => refs = r);
  }
  Future<void> remove(Map<String, Object?> ref) async {
    final yes = await confirmDialog(context, '刪除這張參考臉？', '只刪除參考臉資料，不會刪除原始照片。', confirm: '刪除');
    if (!yes) return;
    await widget.state.deleteRef(ref);
    await load();
  }
  @override Widget build(BuildContext context) {
    final list = refs;
    final legacy = (widget.state.refCounts[widget.name] ?? 0) - (list?.length ?? 0);
    return Scaffold(
      appBar: AppBar(title: Text('「${widget.name}」的參考臉')),
      body: list == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(kPad), children: [
            if (list.isEmpty) const Text('還沒有可顯示的參考臉縮圖。', style: TextStyle(fontSize: 15)),
            if (legacy > 0) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(
              '另有 $legacy 張是舊版登錄的參考臉，沒有縮圖，無法在此單張刪除。', style: const TextStyle(fontSize: 14))),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final r in list) SizedBox(width: 104, child: Column(children: [
                ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 104, height: 104,
                  child: r['crop_path'] != null && File(r['crop_path'] as String).existsSync()
                    ? Image.file(File(r['crop_path'] as String), fit: BoxFit.cover)
                    : const Icon(Icons.broken_image_outlined))),
                TextButton.icon(onPressed: widget.state.busy ? null : () => remove(r),
                  icon: const Icon(Icons.delete_outline, size: 18), label: const Text('刪除')),
              ])),
            ]),
          ]),
    );
  }
}

/// 自我檢查：這是參考檢查，不是身分驗證。
class SelfCheckScreen extends StatefulWidget {
  final AppState state; final String name;
  const SelfCheckScreen({super.key, required this.state, required this.name});
  @override State<SelfCheckScreen> createState() => _SelfCheckScreenState();
}
class _SelfCheckScreenState extends State<SelfCheckScreen> {
  FaceCheckReport? report;
  String? error;
  @override void initState() { super.initState(); run(); }
  Future<void> run() async {
    setState(() { report = null; error = null; });
    try {
      final r = await widget.state.selfCheck(widget.name);
      if (mounted) setState(() => report = r);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }
  Future<void> remove(FaceCheckEntry e) async {
    final yes = await confirmDialog(context, '刪除這張參考臉？', '只刪除參考臉資料，不會刪除原始照片。', confirm: '刪除');
    if (!yes) return;
    await widget.state.deleteRef(e.ref);
    await run();
  }
  @override Widget build(BuildContext context) {
    final r = report;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('自我檢查：${widget.name}')),
      body: error != null
        ? Center(child: Padding(padding: const EdgeInsets.all(kPad),
            child: Text(error!, style: const TextStyle(fontSize: 15), textAlign: TextAlign.center)))
        : r == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(kPad), children: [
              Card(color: scheme.surfaceContainerHighest, child: const Padding(padding: EdgeInsets.all(12),
                child: Text('這只是「參考」檢查：比較各參考臉之間的相似度，找出可能選錯人的臉。'
                    '它不是身分驗證，結果仍需你自己判斷。', style: TextStyle(fontSize: 14)))),
              if (r.unreadable > 0) Padding(padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('有 ${r.unreadable} 張無法讀取，已略過。', style: const TextStyle(fontSize: 14))),
              for (final e in r.entries) ListTile(
                leading: ClipRRect(borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(e.ref['crop_path'] as String), width: 56, height: 56, fit: BoxFit.cover)),
                title: Text('與其他參考臉平均相似度 ${e.mean.toStringAsFixed(2)}'),
                subtitle: e.flagged
                  ? Text('可能選錯臉', style: TextStyle(color: scheme.error, fontWeight: FontWeight.bold))
                  : const Text('看起來一致'),
                trailing: e.flagged ? IconButton(onPressed: () => remove(e),
                  icon: const Icon(Icons.delete_outline), tooltip: '刪除') : null),
            ]),
    );
  }
}
