import 'package:flutter/material.dart';
import '../app_state.dart';
import 'common.dart';

class SettingsTab extends StatelessWidget {
  final AppState state;
  const SettingsTab({super.key, required this.state});

  Future<void> clear(BuildContext context) async {
    final yes = await confirmDialog(context, '清除所有本機索引與標籤？',
      '會清除 AI 索引、家人、標籤、地點與參考臉。不刪除原始照片。', confirm: '清除');
    if (yes) await state.clearLocal();
  }

  @override Widget build(BuildContext context) {
    final s = state;
    final ok = s.ready && !s.busy;
    return ListView(padding: const EdgeInsets.all(kPad), children: [
      StatusArea(state: s),
      Card(child: Padding(padding: const EdgeInsets.all(kPad), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('照片與索引', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('目前已讀取 ${s.assets.length} 張，AI 索引 ${s.rows.values.where((r) => r["vector"] != null).length} 張。',
            style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: ok ? () => s.scan(false) : null,
            icon: const Icon(Icons.photo_library_outlined), label: const Text('讀取照片')),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: ok ? () => s.scan(true) : null,
            icon: const Icon(Icons.auto_awesome_outlined), label: const Text('建立 AI 索引')),
          const SizedBox(height: 4),
          const Text('AI 索引首次需要網路下載模型，可分批、隨時停止；之後可離線語意搜尋。',
            style: TextStyle(fontSize: 13)),
        ]))),
      const Card(child: Padding(padding: EdgeInsets.all(kPad), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('隱私', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('照片、GPS、家人資料與參考臉都只存在這支手機，不會上傳。'
              '家人標籤與地點由你人工確認；人臉比對與語意搜尋只是候選或參考，不是身分或地點證明。',
            style: TextStyle(fontSize: 14)),
        ]))),
      Card(child: Padding(padding: const EdgeInsets.all(kPad), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('清除本機資料', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('不會刪除原始照片。', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: ok ? () => clear(context) : null,
            icon: const Icon(Icons.delete_sweep_outlined), label: const Text('清除本機資料')),
        ]))),
    ]);
  }
}
