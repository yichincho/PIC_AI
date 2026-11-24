import 'package:flutter/material.dart';
import '../app_state.dart';
import '../face_quality.dart';
import 'common.dart';
import 'people_screens.dart';

class PeopleTab extends StatefulWidget {
  final AppState state;
  const PeopleTab({super.key, required this.state});
  @override State<PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<PeopleTab> {
  AppState get s => widget.state;

  Future<void> addPerson() async {
    final yes = await confirmDialog(context, '新增家人',
      '請先取得本人或監護人同意。參考臉與標籤只留在這支手機，不會上傳。', confirm: '繼續');
    if (!yes || !mounted) return;
    final name = await askText(context, '新增家人名稱');
    if (name == null || name.isEmpty) return;
    await s.addPerson(name);
  }

  Future<void> addRefs(String name) async {
    if (s.assets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先到「設定」分頁讀取照片。')));
      return;
    }
    final ids = await Navigator.push<List<String>>(context,
      MaterialPageRoute(builder: (_) => PhotoPickerScreen(state: s, name: name)));
    if (ids == null || ids.isEmpty || !mounted) return;
    final yes = await confirmDialog(context, '確認參考照片',
      '請取得本人或監護人同意。合照可以，若照片中有多張臉，系統會讓你點選是哪一張。資料只留在本機。');
    if (!yes) return;
    await s.enrollFaces(name, ids, (crops) {
      if (!mounted) return Future.value(-2);
      return pickFaceDialog(context, name, crops);
    });
  }

  Future<void> scanFor(String name, int count) async {
    if (count < minRefFaces) {
      final yes = await confirmDialog(context, '參考臉偏少',
        '「$name」目前只有 $count 張參考臉，比對可能不準、漏掉很多。仍要掃描嗎？', confirm: '仍要掃描');
      if (!yes || !mounted) return;
    }
    await s.findFamily(name);
  }

  void push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  Widget step(String no, String title, {String? hint, Widget? action, bool done = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CircleAvatar(radius: 12, child: done ? const Icon(Icons.check, size: 16) : Text(no, style: const TextStyle(fontSize: 12))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        if (hint != null) Text(hint, style: const TextStyle(fontSize: 13)),
        if (action != null) Padding(padding: const EdgeInsets.only(top: 6), child: action),
      ])),
    ]));

  Widget personCard(String name) {
    final scheme = Theme.of(context).colorScheme;
    final count = s.refCounts[name] ?? 0;
    final level = sufficiencyLevel(count);
    final color = switch (level) {
      SufficiencyLevel.insufficient => scheme.error,
      SufficiencyLevel.usable => scheme.primary,
      SufficiencyLevel.good => Colors.green.shade700,
    };
    final pending = s.candidates[name]?.length ?? 0;
    final busy = s.busy;
    return Card(child: Padding(padding: const EdgeInsets.all(kPad), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        step('1', '新增家人', done: true),
        step('2', '選照片點臉',
          hint: '從相簿挑含有「$name」的照片；合照時點選是哪一張臉。',
          action: Wrap(spacing: 8, children: [
            FilledButton(onPressed: busy ? null : () => addRefs(name), child: const Text('加入參考臉')),
            OutlinedButton(onPressed: busy || count == 0 ? null : () => push(ReferenceFacesScreen(state: s, name: name)),
              child: const Text('查看參考臉')),
          ])),
        step('3', '檢查資料量', done: level != SufficiencyLevel.insufficient,
          hint: count >= goodRefFaces ? '參考臉 $count 張' : '參考臉 $count 張；建議再加 ${suggestedMore(count)} 張不同角度、不同時期的照片',
          action: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('資料量：${sufficiencyLabel(level)}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
            ]),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: sufficiencyProgress(count), color: color, minHeight: 6),
            const SizedBox(height: 6),
            OutlinedButton(onPressed: busy || count < minRefFaces ? null : () => push(SelfCheckScreen(state: s, name: name)),
              child: Text(count < minRefFaces ? '自我檢查（至少 $minRefFaces 張）' : '自我檢查')),
          ])),
        step('4', '掃描找$name',
          hint: '用參考臉比對整個相簿，找出候選照片（需要一些時間，可隨時停止）。',
          action: OutlinedButton(onPressed: busy || s.assets.isEmpty || count == 0 ? null : () => scanFor(name, count),
            child: Text('掃描找$name'))),
        step('5', '確認候選',
          hint: pending > 0 ? '有 $pending 張候選等你確認；標籤一定由你人工確認。' : '掃描後在這裡逐張確認。',
          action: OutlinedButton(onPressed: busy || pending == 0 ? null : () => push(CandidateReviewScreen(state: s, name: name)),
            child: const Text('開始確認'))),
      ])));
  }

  @override Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(kPad), children: [
      StatusArea(state: s),
      if (s.people.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('還沒有家人。新增家人後，依步驟加入參考臉、掃描、確認。', style: TextStyle(fontSize: 15))),
      for (final n in s.people) personCard(n),
      Card(child: Padding(padding: const EdgeInsets.all(kPad), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('新增家人', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('請先取得本人或監護人同意。參考臉與標籤只留在這支手機。人臉比對只是候選，不是身分證明。',
            style: TextStyle(fontSize: 14)),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: s.ready && !s.busy ? addPerson : null,
            icon: const Icon(Icons.person_add_alt), label: const Text('新增家人')),
        ]))),
    ]);
  }
}
