import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../app_state.dart';

const kPad = 16.0;

class PhotoThumb extends StatefulWidget {
  final AssetEntity asset; final int size; final BoxFit fit;
  const PhotoThumb({super.key, required this.asset, required this.size, this.fit = BoxFit.cover});
  @override State<PhotoThumb> createState() => _PhotoThumbState();
}
class _PhotoThumbState extends State<PhotoThumb> {
  late Future<Uint8List?> bytes;
  @override void initState() {
    super.initState();
    bytes = widget.asset.thumbnailDataWithSize(ThumbnailSize.square(widget.size));
  }
  @override Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: bytes,
    builder: (ctx, s) => s.data == null
        ? const Center(child: Icon(Icons.photo_outlined))
        : Image.memory(s.data!, fit: widget.fit, gaplessPlayback: true));
}

Future<String?> askText(BuildContext context, String title, [String initial = '']) async {
  final c = TextEditingController(text: initial);
  final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
    title: Text(title), content: TextField(controller: c, autofocus: true),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
      FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('儲存')),
    ],
  ));
  c.dispose();
  return value;
}

Future<bool> confirmDialog(BuildContext context, String title, String message,
    {String confirm = '確認'}) async {
  final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
    title: Text(title), content: Text(message),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirm)),
    ],
  ));
  return yes == true;
}

Future<String?> choosePersonDialog(BuildContext context, String title, List<String> people) {
  return showDialog<String>(context: context, builder: (ctx) => SimpleDialog(
    title: Text(title),
    children: people.map((n) => SimpleDialogOption(
        onPressed: () => Navigator.pop(ctx, n), child: Text(n))).toList(),
  ));
}

/// 回傳被點選的臉索引；-1 = 略過此張；-2 = 取消全部。
Future<int> pickFaceDialog(BuildContext context, String name, List<Uint8List> crops) async {
  final r = await showDialog<int>(context: context, barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text('這張照片中哪一張是「$name」？'),
      content: SingleChildScrollView(child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < crops.length; i++)
          InkWell(onTap: () => Navigator.pop(ctx, i),
            child: Image.memory(crops[i], width: 96, height: 96, fit: BoxFit.cover)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, -1), child: const Text('都不是，略過')),
        TextButton(onPressed: () => Navigator.pop(ctx, -2), child: const Text('取消全部')),
      ]));
  return r ?? -1;
}

/// 忙碌時顯示進度卡；否則顯示最近一次狀態訊息（錯誤以醒目顏色標示）。
class StatusArea extends StatelessWidget {
  final AppState state;
  const StatusArea({super.key, required this.state});
  @override Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (state.busy) {
      return Card(child: Padding(padding: const EdgeInsets.all(kPad), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(state.status.isEmpty ? '處理中…' : state.status, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: state.progress),
          if (state.stoppable) Align(alignment: Alignment.centerRight, child: TextButton.icon(
            onPressed: state.stop ? null : state.requestStop,
            icon: const Icon(Icons.stop_circle_outlined),
            label: Text(state.stop ? '停止中…' : '停止'))),
        ])));
    }
    if (state.status.isEmpty) return const SizedBox.shrink();
    final err = state.statusIsError;
    return Card(
      color: err ? scheme.errorContainer : scheme.surfaceContainerHighest,
      child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(err ? Icons.error_outline : Icons.info_outline,
            color: err ? scheme.onErrorContainer : scheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(child: Text(state.status, style: const TextStyle(fontSize: 14))),
      ])));
  }
}
