import 'package:flutter_test/flutter_test.dart';
import 'package:pic_ai/main.dart';
void main(){
 test('cosine similarity',(){
  expect(cosine([1,0],[1,0]),1);
  expect(cosine([1,0],[0,1]),0);
  expect(cosine([0,0],[1,0]),-1);
  expect(cosine([1],[1,0]),-1);
 });
}
