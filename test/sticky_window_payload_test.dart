import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noterr/models/note.dart';

void main() {
  test('sticky window payload can round trip a note', () {
    final now = DateTime.utc(2026, 5, 22, 12);
    final note = Note(
      type: NoteType.full,
      title: 'Sticky',
      body: 'This should open as a desktop note.',
      colorHex: 'FFF4B8',
      createdAt: now,
      updatedAt: now,
      deviceId: 'test-device',
      boardName: 'Work',
      bounds: const StickyBounds(x: 50, y: 60, width: 320, height: 240),
      isAlwaysOnTop: true,
    );

    final encoded = jsonEncode({
      'type': 'sticky',
      'note': note.toJson(),
    });
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    final restored = Note.fromJson(
      Map<String, dynamic>.from(decoded['note'] as Map),
    );

    expect(decoded['type'], 'sticky');
    expect(restored.type, NoteType.full);
    expect(restored.title, note.title);
    expect(restored.boardName, 'Work');
    expect(restored.bounds?.width, 320);
    expect(restored.isAlwaysOnTop, isTrue);
  });
}
