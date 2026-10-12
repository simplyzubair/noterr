import 'dart:io';

import 'package:flutter/services.dart';

/// File access inside an Obsidian vault, by paths relative to the vault root
/// with `/` separators (for example `Noterr/2026-10-12.md`).
///
/// Desktop vaults are plain folders. On Android, Noterr can't open another
/// app's storage directly: the user picks the vault folder once with the
/// system folder picker and the app keeps a permission (a `content://` tree
/// URI) for that folder only, so every read and write goes through Android's
/// Storage Access Framework instead.
abstract class VaultFs {
  factory VaultFs.forRoot(String root) => root.startsWith('content://')
      ? SafVaultFs(root)
      : IoVaultFs(root);

  /// File contents, or null if the file doesn't exist.
  Future<String?> read(String path);

  /// Creates or replaces the file, creating parent folders as needed.
  Future<void> write(String path, String content);

  /// Last-modified time, or null if the file doesn't exist.
  Future<DateTime?> modified(String path);

  /// Names of the files (not folders) directly inside [dir]; empty if [dir]
  /// doesn't exist.
  Future<List<String>> list(String dir);

  Future<void> delete(String path);
}

class IoVaultFs implements VaultFs {
  IoVaultFs(this.root);

  final String root;

  File _file(String path) => File(_join(path));
  String _join(String path) => [
        root,
        ...path.split('/').where((s) => s.isNotEmpty),
      ].join(Platform.pathSeparator);

  @override
  Future<String?> read(String path) async {
    final f = _file(path);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String path, String content) async {
    final f = _file(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(content, flush: true);
  }

  @override
  Future<DateTime?> modified(String path) async {
    final f = _file(path);
    return await f.exists() ? f.lastModified() : null;
  }

  @override
  Future<List<String>> list(String dir) async {
    final d = Directory(_join(dir));
    if (!await d.exists()) return const [];
    return [
      await for (final e in d.list())
        if (e is File) e.uri.pathSegments.last,
    ];
  }

  @override
  Future<void> delete(String path) async {
    final f = _file(path);
    if (await f.exists()) await f.delete();
  }
}

/// Android Storage Access Framework, implemented in MainActivity.kt.
class SafVaultFs implements VaultFs {
  SafVaultFs(this.treeUri);

  static const _channel = MethodChannel('noterr/vaultfs');

  final String treeUri;

  /// Opens the system folder picker. Returns the folder's tree URI with a
  /// lasting read/write permission, or null if the user cancelled.
  static Future<String?> pickFolder() =>
      _channel.invokeMethod<String>('pickFolder');

  Map<String, Object?> _args(String path, [Map<String, Object?>? more]) =>
      {'tree': treeUri, 'path': path, ...?more};

  @override
  Future<String?> read(String path) =>
      _channel.invokeMethod<String>('read', _args(path));

  @override
  Future<void> write(String path, String content) =>
      _channel.invokeMethod<void>('write', _args(path, {'content': content}));

  @override
  Future<DateTime?> modified(String path) async {
    final ms = await _channel.invokeMethod<int>('modified', _args(path));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  @override
  Future<List<String>> list(String dir) async =>
      (await _channel.invokeListMethod<String>('list', _args(dir))) ??
      const [];

  @override
  Future<void> delete(String path) =>
      _channel.invokeMethod<void>('delete', _args(path));
}
