import 'package:flutter/material.dart';

const notePalette = <String>[
  'FFF4B8',
  'B8F2E6',
  'CDE7FF',
  'FFD6E0',
  'D6F5C9',
  'FFE1B8',
  'E3D7FF',
  'F2F2F2',
];

Color noteColor(String hex) {
  final clean = hex.replaceAll('#', '');
  final value = int.tryParse(clean, radix: 16) ?? 0xFFF4B8;
  return Color(0xFF000000 | value);
}
