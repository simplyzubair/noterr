import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noterr/models/note.dart';
import 'package:noterr/services/obsidian_sync_service.dart';
import 'package:noterr/services/vault_fs.dart';

/// Counts writes, to prove unchanged files aren't rewritten.
class CountingFs implements VaultFs {
  CountingFs(this.inner);
  final VaultFs inner;
  int writes = 0;
  @override
  Future<String?> read(String path) => inner.read(path);
  @override
  Future<void> write(String path, String content) {
    writes++;
    return inner.write(path, content);
  }

  @override
  Future<DateTime?> modified(String path) => inner.modified(path);
  @override
  Future<List<String>> list(String dir) => inner.list(dir);
  @override
  Future<void> delete(String path) => inner.delete(path);
}

Note _board(DateTime day, List<ChecklistItem> items) => Note(
      type: NoteType.full,
      title: 'day',
      body: '',
      colorHex: 'F2F2F2',
      createdAt: day.toUtc(),
      updatedAt: day.toUtc(),
      deviceId: 'phone',
      noteDate: day,
      boardName: 'History',
      isArchived: true,
      checklist: items,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory vault;
  late ObsidianSyncService obsidian;
  late CountingFs fs;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    vault = await Directory.systemTemp.createTemp('noterr-days');
    obsidian = ObsidianSyncService();
    await obsidian.saveConfig(
      ObsidianSyncConfig(vaultPath: vault.path, dailyNotesFolder: 'Noterr'),
    );
    fs = CountingFs(IoVaultFs(vault.path));
    obsidian.fsForTest = fs;
  });

  tearDown(() => vault.delete(recursive: true));

  String day(String name) =>
      File('${vault.path}/Noterr/$name.md').readAsStringSync();

  test('a past day from another device gets its file', () async {
    await obsidian.push(
      _board(DateTime(2026, 10, 9), [ChecklistItem(text: 'Call bank', done: true)]),
      DateTime(2026, 10, 9),
    );
    expect(day('2026-10-09'), contains('- [x] Call bank'));
  });

  test('pushing the same board again does not rewrite the file', () async {
    final board = _board(DateTime(2026, 10, 9), [ChecklistItem(text: 'A')]);
    await obsidian.push(board, DateTime(2026, 10, 9));
    await obsidian.push(board, DateTime(2026, 10, 9));
    expect(fs.writes, 1);
  });

  test('a no-activity day lists open tasks and keeps user text', () async {
    File('${vault.path}/Noterr/2026-10-10.md')
      ..createSync(recursive: true)
      ..writeAsStringSync('My own line\n');
    await obsidian.writeNoActivityDay(DateTime(2026, 10, 10), ['Taxes']);
    final text = day('2026-10-10');
    expect(text, startsWith('My own line'));
    expect(text, contains('_No Noterr activity this day._'));
    expect(text, contains('- [ ] Taxes'));
  });

  test('a no-activity file never replaces a real day', () async {
    await obsidian.push(
      _board(DateTime(2026, 10, 11), [ChecklistItem(text: 'Real task')]),
      DateTime(2026, 10, 11),
    );
    await obsidian.writeNoActivityDay(DateTime(2026, 10, 11), ['Other']);
    expect(day('2026-10-11'), contains('Real task'));
    expect(day('2026-10-11'), isNot(contains('No Noterr activity')));
  });

  test('a real board later replaces a no-activity file', () async {
    await obsidian.writeNoActivityDay(DateTime(2026, 10, 9), const []);
    await obsidian.push(
      _board(DateTime(2026, 10, 9), [ChecklistItem(text: 'Synced late')]),
      DateTime(2026, 10, 9),
    );
    expect(day('2026-10-09'), contains('Synced late'));
    expect(day('2026-10-09'), isNot(contains('No Noterr activity')));
  });
}
