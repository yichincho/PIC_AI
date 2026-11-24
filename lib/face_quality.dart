import 'dart:math' as math;

double cosine(List<double> a, List<double> b) {
  if (a.length != b.length || a.isEmpty) return -1;
  double dot = 0, aa = 0, bb = 0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i]*b[i]; aa += a[i]*a[i]; bb += b[i]*b[i];
  }
  return aa == 0 || bb == 0 ? -1 : dot / math.sqrt(aa*bb);
}

/// 參考臉數量等級：0–2 不足、3–4 可用、5 以上良好。
enum SufficiencyLevel { insufficient, usable, good }

const int minRefFaces = 3;
const int goodRefFaces = 5;

SufficiencyLevel sufficiencyLevel(int count) {
  if (count >= goodRefFaces) return SufficiencyLevel.good;
  if (count >= minRefFaces) return SufficiencyLevel.usable;
  return SufficiencyLevel.insufficient;
}

String sufficiencyLabel(SufficiencyLevel l) => switch (l) {
  SufficiencyLevel.insufficient => '不足',
  SufficiencyLevel.usable => '可用',
  SufficiencyLevel.good => '良好',
};

/// 建議再加幾張（達到良好為止）。
int suggestedMore(int count) => count >= goodRefFaces ? 0 : goodRefFaces - (count < 0 ? 0 : count);

double sufficiencyProgress(int count) {
  if (count <= 0) return 0;
  return count >= goodRefFaces ? 1 : count / goodRefFaces;
}

class FaceCheck {
  final bool enough;
  final List<double> means;
  final List<bool> flagged;
  const FaceCheck(this.enough, this.means, this.flagged);
}

double median(List<double> values) {
  if (values.isEmpty) return 0;
  final s = [...values]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

/// 自我檢查：每張臉對其他臉的平均餘弦相似度；
/// 低於「平均值中位數 − 0.15」或低於 0.35 者標為可疑。至少需要 3 張。
/// 這只是參考檢查，不是身分驗證。
FaceCheck checkFaceConsistency(List<List<double>> embeddings,
    {double gap = 0.15, double floor = 0.35}) {
  final n = embeddings.length;
  if (n < minRefFaces) {
    return FaceCheck(false, List<double>.filled(n, 0), List<bool>.filled(n, false));
  }
  final means = <double>[];
  for (var i = 0; i < n; i++) {
    var sum = 0.0;
    for (var j = 0; j < n; j++) {
      if (i != j) sum += cosine(embeddings[i], embeddings[j]);
    }
    means.add(sum / (n - 1));
  }
  final threshold = median(means) - gap;
  final flagged = [for (final m in means) m < threshold || m < floor];
  return FaceCheck(true, means, flagged);
}
