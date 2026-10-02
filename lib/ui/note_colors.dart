import 'package:flutter/material.dart';

// Obsidian-inspired note palette — muted Catppuccin tones
const notePalette = <String>[
  '2a273f', // mauve (default daily note — deep purple)
  '1e2030', // blue-dark
  '273a2e', // green-dark
  '3a2a1e', // peach-dark
  '2a1e1e', // red-dark
  '1e2a38', // sapphire-dark
  '282a1e', // yellow-dark
  '1e1e2e', // base (neutral)
];

Color noteColor(String hex) {
  final clean = hex.replaceAll('#', '');
  final value = int.tryParse(clean, radix: 16) ?? 0x2a273f;
  return Color(0xFF000000 | value);
}
