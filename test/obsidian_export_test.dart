import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noterr/models/note.dart';
import 'package:noterr/services/obsidian_sync_service.dart';

Note _note({
  String id = 'abcdef1234567890',
  String title = 'Shopping',
  bool archived = false,
  bool deleted = false,
}) {
  final t = DateTime.utc(2026, 10, 8, 9);
  return Note(
    id: id,
    type: NoteType.full,
    title: title,
    body: 'Milk and eggs',
    colorHex: 'FFF4B8',
    createdAt: t,
    updatedAt: t,
    deviceId: 'pc',
    tags: const ['home'],
    checklist: [
      ChecklistItem(text: 'Milk', done: true),
      ChecklistItem(text: 'Eggs'),
    ],
    isArchived: archived,
    isDeleted: deleted,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory vault;
  late ObsidianSyncService obsidian;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    vault = await Directory.systemTemp.createTemp('noterr-vault');
    obsidian = ObsidianSyncService();
    await obsidian.saveConfig(
      ObsidianSyncConfig(vaultPath: vault.path, dailyNotesFolder: 'Noterr'),
    );
  });

  tearDown(() => vault.delete(recursive: true));

  List<String> files() {
    final dir = Directory('${vault.path}/Noterr/Notes');
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList()
      ..sort();
  }

  test('writes a note as markdown with its tasks', () async {
    await obsidian.exportNote(_note());
    expect(files(), ['Shopping (abcdef12).md']);
    final text =
        File('${vault.path}/Noterr/Notes/Shopping (abcdef12).md').readAsStringSync();
    expect(text, contains('noterr_id: abcdef1234567890'));
    expect(text, contains('tags: [home]'));
    expect(text, contains('# Shopping'));
    expect(text, contains('Milk and eggs'));
    expect(text, contains('- [x] Milk'));
    expect(text, contains('- [ ] Eggs'));
  });

  test('a renamed note keeps one file', () async {
    await obsidian.exportNote(_note());
    await obsidian.exportNote(_note(title: 'Groceries: week 41?'));
    expect(files(), ['Groceries week 41 (abcdef12).md']);
  });

  test('deleted and archived notes are removed', () async {
    await obsidian.exportNote(_note());
    await obsidian.exportNote(_note(id: 'ffff000011112222', title: 'Other'));
    await obsidian.exportNote(_note(deleted: true));
    expect(files(), ['Other (ffff0000).md']);
    await obsidian.exportNote(_note(id: 'ffff000011112222', title: 'Other', archived: true));
    expect(files(), isEmpty);
  });

  test('an unchanged note is not rewritten', () async {
    await obsidian.exportNote(_note());
    final file = File('${vault.path}/Noterr/Notes/Shopping (abcdef12).md');
    final before = file.lastModifiedSync();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await obsidian.exportNote(_note());
    expect(file.lastModifiedSync(), before);
  });
}
