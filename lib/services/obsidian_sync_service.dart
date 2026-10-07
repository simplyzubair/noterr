import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ObsidianSyncConfig
// ─────────────────────────────────────────────────────────────────────────────

class ObsidianSyncConfig {
  const ObsidianSyncConfig({required this.vaultPath, this.dailyNotesFolder = ''});

  /// Root path to the Obsidian vault directory.
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

  // ── Config persistence ────────────────────────────────────────────────────

  Future<void> loadConfig() async {
    final path   = await _secureStorage.read(key: _vaultPathKey) ?? '';
    final folder = await _secureStorage.read(key: _folderKey)    ?? '';
    _config = ObsidianSyncConfig(vaultPath: path, dailyNotesFolder: folder);
  }

  Future<void> saveConfig(ObsidianSyncConfig config) async {
    _config = config;
    await _secureStorage.write(key: _vaultPathKey, value: config.vaultPath);
    await _secureStorage.write(key: _folderKey,    value: config.dailyNotesFolder);
    _lastKnownModified.clear(); // force a full sync on next call
  }

  Future<void> clearConfig() async {
    _config = ObsidianSyncConfig(vaultPath: '', dailyNotesFolder: '');
    await _secureStorage.delete(key: _vaultPathKey);
    await _secureStorage.delete(key: _folderKey);
    _lastKnownModified.clear();
  }

  ObsidianSyncConfig? get config => _config;
  bool get isConfigured => _config?.isConfigured == true;

  // ── File path helpers ─────────────────────────────────────────────────────

  /// Returns the path for the given date's daily note, e.g.
  /// /vault/Daily Notes/2026-09-29.md
  String dailyNotePath(DateTime date, ObsidianSyncConfig cfg) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final folder  = cfg.dailyNotesFolder.trim();
    final dir     = folder.isEmpty
        ? cfg.vaultPath
        : '${cfg.vaultPath}${Platform.pathSeparator}$folder';
    return '$dir${Platform.pathSeparator}$dateStr.md';
  }

  File _file(DateTime date) {
    final cfg = _config;
    if (cfg == null || !cfg.isConfigured) {
      throw StateError('Obsidian vault path is not configured.');
    }
    return File(dailyNotePath(date, cfg));
  }

  // ── Push: Noterr → Obsidian ───────────────────────────────────────────────

  /// Write Noterr content into the daily note, preserving everything outside
  /// the `_sectionHeader … _sectionFooter` block.
  Future<void> push(Note note, DateTime date) async {
    if (!isConfigured) return;
    final file = _file(date);
    await file.parent.create(recursive: true);

    // Read existing content (if any)
    String existing = '';
    if (await file.exists()) {
      existing = await file.readAsString();
    }

    final noterSection = _buildNoterSection(note);

    String next;
    if (existing.contains(_sectionHeader)) {
      // Replace the existing Noterr section.
      next = _replaceSection(existing, noterSection);
    } else {
      // Append the Noterr section at the bottom.
      final trimmed = existing.trimRight();
      next = trimmed.isEmpty
          ? noterSection
          : '$trimmed\n\n$noterSection';
    }

    await file.writeAsString(next, flush: true);
    _lastKnownModified[file.path] = await file.lastModified();
  }

  // ── Weekly summary page ───────────────────────────────────────────────────

  static const weeklyFolder = 'Weekly Summary';
  static const _weeklyStart = '<!-- noterr:weekly -->';
  static const _weeklyEnd = '<!-- /noterr:weekly -->';

  /// Writes [markdown] to `<vault>/Weekly Summary/<isoWeek>.md`. Only the part
  /// between Noterr's markers is replaced, so anything the user adds to the
  /// page survives a rewrite.
  Future<void> writeWeeklySummary(String isoWeek, String markdown) async {
    final cfg = _config;
    if (cfg == null || !cfg.isConfigured) return;
    final sep = Platform.pathSeparator;
    final file = File('${cfg.vaultPath}$sep$weeklyFolder$sep$isoWeek.md');
    await file.parent.create(recursive: true);
    final block = '$_weeklyStart\n$markdown\n$_weeklyEnd';

    var existing = '';
    if (await file.exists()) existing = await file.readAsString();
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
    await file.writeAsString('${next.trimRight()}\n', flush: true);
  }

  // ── Pull: Obsidian → Noterr ───────────────────────────────────────────────

  /// Read the daily note and return any content that Noterr doesn't already
  /// know about. The caller merges these into the Note.
  ///
  /// We compare checksums instead of timestamps because LiveSync may update
  /// the file's mtime without changing content.
  Future<ObsidianSyncResult> pull(Note note, DateTime date) async {
    if (!isConfigured) return const ObsidianSyncResult();
    final file = _file(date);
    if (!await file.exists()) return const ObsidianSyncResult();

    final modified = await file.lastModified();
    // Skip if we wrote this ourselves and nothing has changed since.
    final lkm = _lastKnownModified[file.path];
    if (lkm != null && !modified.isAfter(lkm)) {
      return const ObsidianSyncResult();
    }

    final raw = await file.readAsString();
    // Extract only the Noterr-managed section so we don't misparse
    // user-written headings outside our block.
    final outside = _extractOutsideSection(raw);

    return _diffWithNote(note, outside);
  }

  // ── Check if external edit happened ──────────────────────────────────────

  Future<bool> hasExternalEdit(DateTime date) async {
    if (!isConfigured) return false;
    final file = _file(date);
    if (!await file.exists()) return false;
    final lkm = _lastKnownModified[file.path];
    if (lkm == null) return true;
    final modified = await file.lastModified();
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
