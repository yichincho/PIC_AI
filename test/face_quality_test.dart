import 'package:flutter_test/flutter_test.dart';
import 'package:pic_ai/face_quality.dart';

void main() {
  test('sufficiency thresholds', () {
    expect(sufficiencyLevel(0), SufficiencyLevel.insufficient);
    expect(sufficiencyLevel(2), SufficiencyLevel.insufficient);
    expect(sufficiencyLevel(3), SufficiencyLevel.usable);
    expect(sufficiencyLevel(4), SufficiencyLevel.usable);
    expect(sufficiencyLevel(5), SufficiencyLevel.good);
    expect(sufficiencyLevel(12), SufficiencyLevel.good);
  });

  test('suggested more and progress', () {
    expect(suggestedMore(0), 5);
    expect(suggestedMore(3), 2);
    expect(suggestedMore(5), 0);
    expect(suggestedMore(9), 0);
    expect(sufficiencyProgress(0), 0);
    expect(sufficiencyProgress(2), closeTo(0.4, 1e-9));
    expect(sufficiencyProgress(8), 1);
  });

  test('fewer than 3 faces cannot be checked', () {
    final r = checkFaceConsistency([[1.0, 0.0], [0.0, 1.0]]);
    expect(r.enough, false);
    expect(r.flagged, [false, false]);
    expect(checkFaceConsistency([]).enough, false);
  });

  test('obvious outlier is flagged', () {
    final r = checkFaceConsistency([
      [1.0, 0.0],
      [1.0, 0.1],
      [1.0, -0.1],
      [0.0, 1.0],
    ]);
    expect(r.enough, true);
    expect(r.flagged, [false, false, false, true]);
  });

  test('consistent faces are not flagged', () {
    final r = checkFaceConsistency([
      [1.0, 0.0],
      [1.0, 0.0],
      [1.0, 0.0],
    ]);
    expect(r.enough, true);
    expect(r.flagged, [false, false, false]);
  });

  test('median', () {
    expect(median([3.0, 1.0, 2.0]), 2.0);
    expect(median([1.0, 2.0, 3.0, 4.0]), 2.5);
    expect(median([]), 0);
  });
}
