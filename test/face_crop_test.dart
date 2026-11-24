import 'package:flutter_test/flutter_test.dart';
import 'package:pic_ai/face_crop.dart';

void main() {
  test('center box expands by margin and stays square', () {
    final r = expandFaceRect(left: 400, top: 400, width: 100, height: 100, imageWidth: 1000, imageHeight: 1000);
    expect(r.w, 170);
    expect(r.h, 170);
    expect(r.x, 365);
    expect(r.y, 365);
  });

  test('box at image edge is clamped inside image', () {
    final r = expandFaceRect(left: 0, top: 0, width: 100, height: 100, imageWidth: 1000, imageHeight: 1000);
    expect(r.x, 0);
    expect(r.y, 0);
    expect(r.w, 170);
    final r2 = expandFaceRect(left: 920, top: 920, width: 80, height: 80, imageWidth: 1000, imageHeight: 1000);
    expect(r2.x + r2.w, lessThanOrEqualTo(1000));
    expect(r2.y + r2.h, lessThanOrEqualTo(1000));
  });

  test('non-square box becomes square using the longer side', () {
    final r = expandFaceRect(left: 300, top: 300, width: 100, height: 200, imageWidth: 1000, imageHeight: 1000);
    expect(r.w, r.h);
    expect(r.w, 340);
  });

  test('tiny image never yields empty or out-of-range rect', () {
    final r = expandFaceRect(left: 1, top: 1, width: 50, height: 50, imageWidth: 10, imageHeight: 8);
    expect(r.w, greaterThanOrEqualTo(1));
    expect(r.h, greaterThanOrEqualTo(1));
    expect(r.x + r.w, lessThanOrEqualTo(10));
    expect(r.y + r.h, lessThanOrEqualTo(8));
    final z = expandFaceRect(left: 0, top: 0, width: 0, height: 0, imageWidth: 1, imageHeight: 1);
    expect(z.w, 1);
    expect(z.h, 1);
  });
}
