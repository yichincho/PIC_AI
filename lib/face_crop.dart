import 'dart:typed_data';
import 'package:image/image.dart' as img;

typedef FaceBox = ({double left, double top, double width, double height});

/// 將人臉框向外擴張 [margin]（每邊佔框大小的比例），轉為正方形並限制在圖片範圍內。
({int x, int y, int w, int h}) expandFaceRect({
  required double left,
  required double top,
  required double width,
  required double height,
  required int imageWidth,
  required int imageHeight,
  double margin = 0.35,
}) {
  final iw = imageWidth < 1 ? 1 : imageWidth;
  final ih = imageHeight < 1 ? 1 : imageHeight;
  final cx = left + width / 2;
  final cy = top + height / 2;
  final side = (width > height ? width : height) * (1 + 2 * margin);
  final maxSide = (iw < ih ? iw : ih).toDouble();
  final s = side > maxSide ? maxSide : (side < 1 ? 1.0 : side);
  var x = cx - s / 2;
  var y = cy - s / 2;
  if (x < 0) x = 0;
  if (y < 0) y = 0;
  if (x + s > iw) x = iw - s;
  if (y + s > ih) y = ih - s;
  final xi = x.floor().clamp(0, iw - 1).toInt();
  final yi = y.floor().clamp(0, ih - 1).toInt();
  final sideI = s.round().clamp(1, (iw - xi) < (ih - yi) ? (iw - xi) : (ih - yi)).toInt();
  return (x: xi, y: yi, w: sideI, h: sideI);
}

/// 依人臉框裁切 JPEG，回傳每張臉的 JPEG（品質 92）。無法解碼時丟出 StateError。
List<Uint8List> cropFaces(Uint8List jpeg, List<FaceBox> boxes) {
  final decoded = img.decodeImage(jpeg);
  if (decoded == null) throw StateError('無法解碼照片');
  final image = img.bakeOrientation(decoded);
  return [
    for (final b in boxes)
      () {
        final r = expandFaceRect(
          left: b.left, top: b.top, width: b.width, height: b.height,
          imageWidth: image.width, imageHeight: image.height,
        );
        final c = img.copyCrop(image, x: r.x, y: r.y, width: r.w, height: r.h);
        return Uint8List.fromList(img.encodeJpg(c, quality: 92));
      }(),
  ];
}
