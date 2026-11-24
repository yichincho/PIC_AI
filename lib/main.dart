import 'package:flutter/material.dart';
import 'ui/home.dart';

export 'face_quality.dart' show cosine;

void main() => runApp(MaterialApp(
  debugShowCheckedModeBanner: false,
  title: 'PIC_AI',
  theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
  home: const Home(),
));
