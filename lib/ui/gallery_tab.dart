import 'package:flutter/material.dart';
import '../app_state.dart';
import 'common.dart';

class GalleryTab extends StatefulWidget {
  final AppState state;
  const GalleryTab({super.key, required this.state});
  @override State<GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends State<GalleryTab> {
  final query = TextEditingController();
  AppState get s => widget.state;
  @override void dispose() { query.dispose(); super.dispose(); }

  Future<void> tag() async {
    if (s.people.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先到「家人」分頁新增家人。')));
      return;
    }
    final person = await choosePersonDialog(context, '將已選照片標記為家人（人工確認）', s.people);
    if (person != null) await s.tagSelected(person);
  }

  Future<void> place() async {
    final name = await askText(context, '將已選照片標記為同一人工確認地點');
    if (name != null && name.isNotEmpty) await s.placeSelected(name);
  }

  Widget onboarding() => Card(child: Padding(padding: const EdgeInsets.all(kPad), child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('歡迎使用 PIC_AI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('所有照片與資料都只留在這支手機。請依序完成：', style: TextStyle(fontSize: 14)),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: s.busy ? null : () => s.scan(false),
        icon: const Icon(Icons.photo_library_outlined), label: const Text('步驟 1：讀取照片')),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: s.busy || s.assets.isEmpty ? null : () => s.scan(true),
        icon: const Icon(Icons.auto_awesome_outlined), label: const Text('步驟 2：建立 AI 索引（可稍後）')),
      const SizedBox(height: 4),
      const Text('AI 索引首次需要網路下載模型，之後可離線搜尋。', style: TextStyle(fontSize: 13)),
    ])));

  Widget filters() => SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
    PopupMenuButton<String>(
      enabled: !s.busy,
      onSelected: (n) => s.setPersonFilter(n),
      itemBuilder: (_) => [
        const PopupMenuItem(value: '', child: Text('所有家人')),
        ...s.people.map((n) => PopupMenuItem(value: n, child: Text(n))),
      ],
      child: Chip(avatar: const Icon(Icons.person_outline, size: 18),
        label: Text(s.personFilter.isEmpty ? '家人' : s.personFilter)),
    ),
    const SizedBox(width: 8),
    ActionChip(avatar: const Icon(Icons.place_outlined, size: 18),
      label: Text(s.placeFilter.isEmpty ? '地點' : s.placeFilter),
      onPressed: s.busy ? null : () async {
        final n = await askText(context, '搜尋人工確認地點', s.placeFilter);
        if (n != null) await s.setPlaceFilter(n);
      }),
    const SizedBox(width: 8),
    FilterChip(label: const Text('缺少 GPS'), selected: s.missing,
      onSelected: s.busy ? null : (v) => s.setMissing(v)),
    if (s.ranked) ...[
      const SizedBox(width: 8),
      ActionChip(avatar: const Icon(Icons.close, size: 18),
        label: Text(s.candidateMode ? '結束候選檢視' : '取消語意排序'),
        onPressed: s.busy ? null : () => s.clearRanking()),
    ],
  ]));

  Widget actionBar() => Material(elevation: 6, child: SafeArea(top: false, child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(children: [
      Text('已選 ${s.selected.length} 張', style: const TextStyle(fontSize: 15)),
      const Spacer(),
      FilledButton(onPressed: s.busy ? null : tag, child: const Text('標記家人')),
      const SizedBox(width: 8),
      OutlinedButton(onPressed: s.busy ? null : place, child: const Text('設定地點')),
      TextButton(onPressed: s.clearSelection, child: const Text('取消選取')),
    ]))));

  @override Widget build(BuildContext context) {
    return Column(children: [
      Expanded(child: CustomScrollView(slivers: [
        SliverPadding(padding: const EdgeInsets.fromLTRB(kPad, kPad, kPad, 8), sliver: SliverList(delegate: SliverChildListDelegate([
          StatusArea(state: s),
          if (s.showOnboarding) onboarding(),
          TextField(controller: query, enabled: !s.busy,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => s.search(query.text),
            decoration: InputDecoration(
              hintText: '語意搜尋，例如：日本寺廟、海邊、生日蛋糕',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(onPressed: s.busy ? null : () => s.search(query.text),
                icon: const Icon(Icons.search), tooltip: '搜尋'))),
          const SizedBox(height: 8),
          filters(),
          const SizedBox(height: 8),
          Text(s.candidateMode
              ? '目前為人臉候選檢視；請到「家人」分頁的「確認候選」逐張確認。'
              : '家人標籤為人工確認；點選照片可多選，長按查看地點線索。',
            style: const TextStyle(fontSize: 13)),
        ]))),
        SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 2), sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
          delegate: SliverChildBuilderDelegate((context, i) {
            final id = s.results[i];
            return GestureDetector(
              onTap: s.busy ? null : () => s.toggleSelect(id),
              onLongPress: s.busy ? null : () => showPhotoDetail(context, s, id),
              child: Stack(fit: StackFit.expand, children: [
                PhotoThumb(key: ValueKey(id), asset: s.assets[id]!, size: 240),
                if (s.selected.contains(id)) const Align(alignment: Alignment.topRight,
                  child: Padding(padding: EdgeInsets.all(2), child: Icon(Icons.check_circle, color: Colors.green))),
                if (s.rows[id]?['lat'] == null) const Align(alignment: Alignment.bottomLeft,
                  child: Padding(padding: EdgeInsets.all(2), child: Icon(Icons.location_off, color: Colors.orange))),
              ]));
          }, childCount: s.results.length),
        )),
      ])),
      if (s.selected.isNotEmpty) actionBar(),
    ]);
  }
}

Future<void> showPhotoDetail(BuildContext context, AppState s, String id) async {
  final r = s.rows[id];
  if (r == null) return;
  final shot = r['shot'] as int;
  final near = s.rows.values.where((x) => x['id'] != id && x['lat'] != null
      && ((x['shot'] as int) - shot).abs() <= 30 * 60 * 1000).toList()
    ..sort((a, b) => ((a['shot'] as int) - shot).abs().compareTo(((b['shot'] as int) - shot).abs()));
  final tags = await s.db!.query('tags', where: 'photo=?', whereArgs: [id]);
  if (!context.mounted) return;
  await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
    title: const Text('照片與地點線索'),
    content: SizedBox(width: 360, child: SingleChildScrollView(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        PhotoThumb(asset: s.assets[id]!, size: 700),
        Text('拍攝：${DateTime.fromMillisecondsSinceEpoch(shot)}'),
        Text('原始 GPS：${r["lat"] == null ? "無或無法讀取" : "${r["lat"]}, ${r["lon"]}"}'),
        Text('人工確認地點：${r["place"]}'),
        Text('人工家人標籤：${tags.map((t) => t["person"]).join("、")}'),
        if (r['lat'] == null) ...[
          const Text('前後 30 分鐘有 GPS 的照片（僅供推測，非原始定位）'),
          if (near.isEmpty) const Text('未找到時間線索'),
          for (final x in near.take(5)) ListTile(
            leading: SizedBox(width: 50, height: 50, child: PhotoThumb(asset: s.assets[x['id']]!, size: 120)),
            title: Text('${x["lat"]}, ${x["lon"]}'),
            subtitle: Text('相隔 ${((x["shot"] as int) - shot).abs() ~/ 60000} 分鐘'),
          ),
        ],
      ]))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉')),
      TextButton(onPressed: () async {
        Navigator.pop(ctx);
        final name = await askText(context, '人工確認地點（不改原照片）', r['place'] as String? ?? '');
        if (name == null) return;
        await s.setPlace(id, name);
      }, child: const Text('編輯地點')),
    ],
  ));
}
