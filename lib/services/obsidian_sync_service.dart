import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import 'vault_fs.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ObsidianSyncConfig
// ─────────────────────────────────────────────────────────────────────────────

class ObsidianSyncConfig {
  const ObsidianSyncConfig({required this.vaultPath, this.dailyNotesFolder = ''});

  /// Root of the Obsidian vault: a folder path on desktop, or the
  /// `content://` tree URI of the folder picked on Android.
  final String vaultPath;

  /// Sub-folder inside the vault where daily notes live.
  /// Leave empty to put them in the vault root.
  /// Common: 'Daily Notes', 'Journal', '00-Inbox/Daily'.
  final String dailyNotesFolder;

  bool get isConfigured => vaultPath.trim().isNotEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
// ObsidianSyncResult — returned by pull/push so the controller can decide what
// changed.
// ─────────────────────────────────────────────────────────────────────────────

class ObsidianSyncResult {
  const ObsidianSyncResult({
    this.addedBodyLines = const [],
    this.addedTasks = const [],
    this.updatedTasks = const [],
    this.error,
  });

  final List<String> addedBodyLines;
  final List<ObsidianTask> addedTasks;
  final List<ObsidianTask> updatedTasks;
  final String? error;

  bool get hasChanges =>
      addedBodyLines.isNotEmpty ||
      addedTasks.isNotEmpty ||
      updatedTasks.isNotEmpty;
  bool get hasError => error != null;
}

// Internal representation of a task parsed from the markdown file.
class ObsidianTask {
  const ObsidianTask({required this.text, required this.done});
  final String text;
  final bool done;
}

// ─────────────────────────────────────────────────────────────────────────────
// ObsidianSyncService
// ─────────────────────────────────────────────────────────────────────────────

class ObsidianSyncService {
  ObsidianSyncService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _vaultPathKey  = 'noterr_obsidian_vault_path';
  static const _folderKey     = 'noterr_obsidian_folder';
  // Marker inserted in the daily note to delimit the Noterr section.
  static const _sectionHeader = '## 📌 Noterr';
  static const _sectionFooter = '<!-- /noterr -->';

  final FlutterSecureStorage _secureStorage;

  // Last-modified timestamp of the daily note when we last pushed.
  // Used to detect external edits (Obsidian or LiveSync).
  // Keyed by file path: Noterr can write tomorrow's note as well as today's,
  // and one shared timestamp would hide external edits to the other file.
  final Map<String, DateTime> _lastKnownModified = {};
  // Config loaded at startup / after user sets vault path.
  ObsidianSyncConfig? _config;
  VaultFs? _fs;

  /// Lets tests use a fake vault.
  set fsForTest(VaultFs fs) => _fs = fs;

  VaultFs get _vault {
    final cfg = _config;
    if (cfg == null || !cfg.isConfigured) {
      throw StateError('Obsidian vault path is not configured.');
    }
    return _fs ??= VaultFs.forRoot(cfg.vaultPath.trim());
  }

  /// The folder Noterr writes into, relative to the vault root.
  String get _noterrFolder =>
      (_config?.dailyNotesFolder ?? '').trim().replaceAll(r'\', '/');

  // ── Config persistence ────────────────────────────────────────────────────

  Future<void> loadConfig() async {
    final path   = await _secureStorage.read(key: _vaultPathKey) ?? '';
    final folder = await _secureStorage.read(key: _folderKey)    ?? '';
    _config = ObsidianSyncConfig(vaultPath: path, dailyNotesFolder: folder);
    _fs = null;
  }

  Future<void> saveConfig(ObsidianSyncConfig config) async {
    _config = config;
    _fs = null;
    await _secureStorage.write(key: _vaultPathKey, value: config.vaultPath);
    await _secureStorage.write(key: _folderKey,    value: config.dailyNotesFolder);
    _lastKnownModified.clear(); // force a full sync on next call
  }

  Future<void> clearConfig() async {
    _config = ObsidianSyncConfig(vaultPath: '', dailyNotesFolder: '');
    _fs = null;
    await _secureStorage.delete(key: _vaultPathKey);
    await _secureStorage.delete(key: _folderKey);
    _lastKnownModified.clear();
  }

  ObsidianSyncConfig? get config => _config;
  bool get isConfigured => _config?.isConfigured == true;

  // ── File path helpers ─────────────────────────────────────────────────────

  /// Vault-relative path of a day's note, e.g. `Noterr/2026-09-29.md`.
  String _dailyRel(DateTime date) {
    final name = '${DateFormat('yyyy-MM-dd').format(date)}.md';
    return _noterrFolder.isEmpty ? name : '$_noterrFolder/$name';
  }

  /// Writes [content] unless the file already holds exactly that, so devices
  /// writing the same notes (PC and phone) don't churn LiveSync.
  Future<void> _writeIfChanged(String path, String content) async {
    if (await _vault.read(path) == content) return;
    await _vault.write(path, content);
  }

  // ── Push: Noterr → Obsidian ───────────────────────────────────────────────

  /// Write Noterr content into the daily note, preserving everything outside
  /// the `_sectionHeader … _sectionFooter` block.
  Future<void> push(Note note, DateTime date) =>
      _writeDaySection(date, _buildNoterSection(note));

  /// For a day on which no device opened Noterr: a file saying so, with the
  /// tasks that were still open, so the vault has no missing days. Leaves a
  /// day alone if it already has a Noterr section.
  Future<void> writeNoActivityDay(DateTime date, List<String> openTasks) async {
    if (!isConfigured) return;
    final existing = await _vault.read(_dailyRel(date)) ?? '';
    if (existing.contains(_sectionHeader)) return;
    final buf = StringBuffer()
      ..writeln(_sectionHeader)
      ..writeln()
      ..writeln('_No Noterr activity this day._')
      ..writeln();
    if (openTasks.isNotEmpty) {
      buf.writeln('Still open:');
      for (final t in openTasks) {
        buf.writeln('- [ ] $t');
      }
      buf.writeln();
    }
    buf.write(_sectionFooter);
    await _writeDaySection(date, buf.toString());
  }

  Future<void> _writeDaySection(DateTime date, String section) async {
    if (!isConfigured) return;
    final path = _dailyRel(date);
    final existing = await _vault.read(path) ?? '';
    final String next;
    if (existing.contains(_sectionHeader)) {
      next = _replaceSection(existing, section);
    } else {
      final trimmed = existing.trimRight();
      next = trimmed.isEmpty ? section : '$trimmed\n\n$section';
    }
    await _writeIfChanged(path, next);
    final mod = await _vault.modified(path);
    if (mod != null) _lastKnownModified[path] = mod;
  }

  // ── Other notes (stickies, checklists) ────────────────────────────────────

  static const notesSubfolder = 'Notes';

  String get _notesRel {
    final folder = _noterrFolder.isEmpty ? 'Noterr' : _noterrFolder;
    return '$folder/$notesSubfolder';
  }

  /// Mirrors one non-daily note to `<Noterr folder>/Notes/<title> (<id>).md`.
  /// One-way: Noterr owns these files and rewrites them whole. The id in the
  /// name keeps a renamed note on one file. A deleted or archived note's file
  /// is removed. Unchanged notes aren't rewritten, so LiveSync stays quiet.
  Future<void> exportNote(Note note) async {
    if (!isConfigured) return;
    final dir = _notesRel;
    final shortId = note.id.length > 8 ? note.id.substring(0, 8) : note.id;
    final idTag = '($shortId).md';
    final remove = note.isDeleted || note.isArchived;
    final name = '${_safeFileName(note.title)} $idTag';

    for (final existing in await _vault.list(dir)) {
      if (existing.endsWith(idTag) && (remove || existing != name)) {
        await _vault.delete('$dir/$existing');
      }
    }
    if (remove) return;
    await _writeIfChanged('$dir/$name', _noteMarkdown(note));
  }

  String _noteMarkdown(Note note) {
    final title = note.title.trim().isEmpty ? 'Untitled' : note.title.trim();
    final b = StringBuffer()
      ..writeln('---')
      ..writeln('noterr_id: ${note.id}')
      ..writeln('board: ${note.boardName}');
    if (note.tags.isNotEmpty) {
      b.writeln('tags: [${note.tags.map((t) => t.replaceAll(',', ' ')).join(', ')}]');
    }
    b
      ..writeln('updated: ${note.updatedAt.toUtc().toIso8601String()}')
      ..writeln('---')
      ..writeln()
      ..writeln('# $title')
      ..writeln();
    final body = note.body.trim();
    if (body.isNotEmpty) {
      b
        ..writeln(body)
        ..writeln();
    }
    for (final item in note.checklist) {
      final text = item.text.trim();
      if (text.isEmpty) continue;
      b.writeln('- [${item.done ? 'x' : ' '}] $text');
    }
    return '${b.toString().trimRight()}\n';
  }

  static String _safeFileName(String title) {
    final cleaned = title
        .replaceAll(RegExp(r'[\\/:*?"<>|#^\[\]\n\r\t]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'Untitled';
    return cleaned.length > 60 ? cleaned.substring(0, 60).trim() : cleaned;
  }

  // ── Weekly summary page ───────────────────────────────────────────────────

  static const weeklyFolder = 'Weekly Summary';
  static const _weeklyStart = '<!-- noterr:weekly -->';
  static const _weeklyEnd = '<!-- /noterr:weekly -->';

  /// Writes [markdown] to `<vault>/Weekly Summary/<isoWeek>.md`. Only the part
  /// between Noterr's markers is replaced, so anything the user adds to the
  /// page survives a rewrite.
  Future<void> writeWeeklySummary(String isoWeek, String markdown) async {
    if (!isConfigured) return;
    final path = '$weeklyFolder/$isoWeek.md';
    final block = '$_weeklyStart\n$markdown\n$_weeklyEnd';

    final existing = await _vault.read(path) ?? '';
    final start = existing.indexOf(_weeklyStart);
    final end = start == -1 ? -1 : existing.indexOf(_weeklyEnd, start);
    final String next;
    if (start == -1 || end == -1) {
      final trimmed = existing.trimRight();
      next = trimmed.isEmpty ? block : '$block\n\n$trimmed';
    } else {
      next = existing.substring(0, start) +
          block +
          existing.substring(end + _weeklyEnd.length);
    }
    await _writeIfChanged(path, '${next.trimRight()}\n');
  }

  // ── Pull: Obsidian → Noterr ───────────────────────────────────────────────

  /// Read the daily note and return any content that Noterr doesn't already
  /// know about. The caller merges these into the Note.
  ///
  /// We compare checksums instead of timestamps because LiveSync may update
  /// the file's mtime without changing content.
  Future<ObsidianSyncResult> pull(Note note, DateTime date) async {
    if (!isConfigured) return const ObsidianSyncResult();
    final path = _dailyRel(date);
    final modified = await _vault.modified(path);
    if (modified == null) return const ObsidianSyncResult();
    // Skip if we wrote this ourselves and nothing has changed since.
    final lkm = _lastKnownModified[path];
    if (lkm != null && !modified.isAfter(lkm)) {
      return const ObsidianSyncResult();
    }

    final raw = await _vault.read(path) ?? '';
    // Extract only the Noterr-managed section so we don't misparse
    // user-written headings outside our block.
    final outside = _extractOutsideSection(raw);

    return _diffWithNote(note, outside);
  }

  // ── Check if external edit happened ──────────────────────────────────────

  Future<bool> hasExternalEdit(DateTime date) async {
    if (!isConfigured) return false;
    final path = _dailyRel(date);
    final modified = await _vault.modified(path);
    if (modified == null) return false;
    final lkm = _lastKnownModified[path];
    if (lkm == null) return true;
    return modified.isAfter(lkm);
  }

  // ── Section builder ───────────────────────────────────────────────────────

  String _buildNoterSection(Note note) {
    final buf = StringBuffer();
    buf.writeln(_sectionHeader);
    buf.writeln();

    // Body text (free notes)
    final body = note.body.trim();
    if (body.isNotEmpty) {
      buf.writeln(body);
      buf.writeln();
    }

    // Checklist tasks
    if (note.checklist.isNotEmpty) {
      for (final item in note.checklist) {
        final text = item.text.trim();
        if (text.isEmpty) continue;
        final marker = item.done ? '[x]' : '[ ]';
        buf.writeln('- $marker $text');
      }
      buf.writeln();
    }

    buf.write(_sectionFooter);
    return buf.toString();
  }

  String _replaceSection(String content, String newSection) {
    final start = content.indexOf(_sectionHeader);
    if (start == -1) return content;
    final end = content.indexOf(_sectionFooter, start);
    if (end == -1) {
      // Footer missing — replace from header to end of file.
      return '${content.substring(0, start).trimRight()}\n\n$newSection';
    }
    final after = content.substring(end + _sectionFooter.length);
    final before = content.substring(0, start).trimRight();
    return before.isEmpty
        ? '$newSection${after.trimRight()}'.trim()
        : '$before\n\n$newSection${after.trimRight()}'.trimRight();
  }

  /// Returns the content of the file that is OUTSIDE the Noterr section.
  /// This is what the user typed directly in Obsidian.
  String _extractOutsideSection(String content) {
    final start = content.indexOf(_sectionHeader);
    if (start == -1) return content.trim();
    final end = content.indexOf(_sectionFooter, start);
    final before = content.substring(0, start).trim();
    final after  = end == -1
        ? ''
        : content.substring(end + _sectionFooter.length).trim();
    return [before, after].where((s) => s.isNotEmpty).join('\n\n');
  }

  // ── Diff ──────────────────────────────────────────────────────────────────

  ObsidianSyncResult _diffWithNote(Note note, String obsidianOutside) {
    if (obsidianOutside.trim().isEmpty) return const ObsidianSyncResult();

    final existingBody  = note.body.trim().toLowerCase();
    final existingTexts = note.checklist
        .map((item) => item.text.trim().toLowerCase())
        .toSet();

    final addedBodyLines = <String>[];
    final addedTasks     = <ObsidianTask>[];
    final updatedTasks   = <ObsidianTask>[];

    for (final rawLine in obsidianOutside.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Detect markdown checkbox: `- [ ] text` or `- [x] text`
      final taskMatch = RegExp(r'^-\s+\[( |x|X)\]\s+(.+)$').firstMatch(line);
      if (taskMatch != null) {
        final done = taskMatch.group(1)!.toLowerCase() == 'x';
        final text = taskMatch.group(2)!.trim();
        if (text.isEmpty) continue;

        final key = text.toLowerCase();
        if (!existingTexts.contains(key)) {
          addedTasks.add(ObsidianTask(text: text, done: done));
        } else {
          // Check if the done-state differs from Noterr
          final existing = note.checklist.firstWhere(
            (item) => item.text.trim().toLowerCase() == key,
          );
          if (existing.done != done) {
            updatedTasks.add(ObsidianTask(text: text, done: done));
          }
        }
        continue;
      }

      // Plain text line — add to body if not already present
      final key = line.toLowerCase();
      if (!existingBody.contains(key)) {
        addedBodyLines.add(line);
      }
    }

    return ObsidianSyncResult(
      addedBodyLines: addedBodyLines,
      addedTasks:     addedTasks,
      updatedTasks:   updatedTasks,
    );
  }

  // ── Utility ───────────────────────────────────────────────────────────────

  /// Ensures the vault folder exists and is readable.
  static Future<String?> validateVaultPath(String path) async {
    if (path.trim().isEmpty) return 'Path cannot be empty.';
    final dir = Directory(path.trim());
    if (!await dir.exists()) return 'Folder does not exist: $path';
    // Check for .obsidian marker
    final marker = Directory('${dir.path}${Platform.pathSeparator}.obsidian');
    if (!await marker.exists()) {
      return 'This does not look like an Obsidian vault (.obsidian folder not found). Proceed anyway?';
    }
    return null; // valid
  }
}
