import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class StickyBounds {
  const StickyBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory StickyBounds.defaults() =>
      const StickyBounds(x: 80, y: 80, width: 320, height: 260);

  factory StickyBounds.fromJson(Map<String, dynamic>? json) {
    if (json == null) return StickyBounds.defaults();
    return StickyBounds(
      x: (json['x'] as num?)?.toDouble() ?? 80,
      y: (json['y'] as num?)?.toDouble() ?? 80,
      width: (json['width'] as num?)?.toDouble() ?? 320,
      height: (json['height'] as num?)?.toDouble() ?? 260,
    );
  }

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };
}

class ChecklistItem {
  ChecklistItem({
    String? id,
    required this.text,
    this.done = false,
    this.isFocus = false,
    this.carriedFrom,
    this.reminderAt,
    this.reminderDone = false,
  }) : id = id ?? _uuid.v4();

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
        id: json['id'] as String?,
        text: json['text'] as String? ?? '',
        done: json['done'] as bool? ?? false,
        isFocus: json['isFocus'] as bool? ?? false,
        carriedFrom: json['carriedFrom'] == null
            ? null
            : DateTime.tryParse(json['carriedFrom'] as String)?.toUtc(),
        reminderAt: json['reminderAt'] == null
            ? null
            : DateTime.tryParse(json['reminderAt'] as String)?.toUtc(),
        reminderDone: json['reminderDone'] as bool? ?? false,
      );

  final String id;
  final String text;
  final bool done;
  final bool isFocus;
  final DateTime? carriedFrom;
  final DateTime? reminderAt;
  final bool reminderDone;

  ChecklistItem copyWith({
    String? text,
    bool? done,
    bool? isFocus,
    DateTime? carriedFrom,
    bool clearCarriedFrom = false,
    DateTime? reminderAt,
    bool clearReminder = false,
    bool? reminderDone,
  }) =>
      ChecklistItem(
        id: id,
        text: text ?? this.text,
        done: done ?? this.done,
        isFocus: isFocus ?? this.isFocus,
        carriedFrom:
            clearCarriedFrom ? null : carriedFrom ?? this.carriedFrom,
        reminderAt: clearReminder ? null : reminderAt ?? this.reminderAt,
        reminderDone: reminderDone ?? this.reminderDone,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'done': done,
        'isFocus': isFocus,
        'carriedFrom': carriedFrom?.toIso8601String(),
        'reminderAt': reminderAt?.toIso8601String(),
        'reminderDone': reminderDone,
      };
}

class NoteReminder {
  const NoteReminder({
    required this.dueAt,
    this.repeatRule,
    this.completed = false,
  });

  factory NoteReminder.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const NoteReminder(dueAt: null);
    return NoteReminder(
      dueAt: json['dueAt'] == null
          ? null
          : DateTime.tryParse(json['dueAt'] as String),
      repeatRule: json['repeatRule'] as String?,
      completed: json['completed'] as bool? ?? false,
    );
  }

  final DateTime? dueAt;
  final String? repeatRule;
  final bool completed;

  bool get isSet => dueAt != null;

  Map<String, dynamic> toJson() => {
        'dueAt': dueAt?.toIso8601String(),
        'repeatRule': repeatRule,
        'completed': completed,
      };
}

class NoteAttachment {
  NoteAttachment({
    String? id,
    required this.name,
    required this.mimeType,
    this.localPath,
    this.remotePath,
    this.sizeBytes = 0,
  }) : id = id ?? _uuid.v4();

  factory NoteAttachment.fromJson(Map<String, dynamic> json) => NoteAttachment(
        id: json['id'] as String?,
        name: json['name'] as String? ?? 'Attachment',
        mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
        localPath: json['localPath'] as String?,
        remotePath: json['remotePath'] as String?,
        sizeBytes: json['sizeBytes'] as int? ?? 0,
      );

  final String id;
  final String name;
  final String mimeType;
  final String? localPath;
  final String? remotePath;
  final int sizeBytes;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mimeType': mimeType,
        'localPath': localPath,
        'remotePath': remotePath,
        'sizeBytes': sizeBytes,
      };
}

enum NoteType {
  note,
  checklist,
  full;

  static NoteType fromJson(String? value) {
    return NoteType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => NoteType.full,
    );
  }

  String get label {
    return switch (this) {
      NoteType.note => 'Note',
      NoteType.checklist => 'Checklist',
      NoteType.full => 'Full Editor',
    };
  }
}

class Note {
  Note({
    String? id,
    this.type = NoteType.full,
    required this.title,
    required this.body,
    required this.colorHex,
    required this.createdAt,
    required this.updatedAt,
    required this.deviceId,
    this.revision = 1,
    this.boardName = 'Personal',
    this.tags = const [],
    this.checklist = const [],
    this.attachments = const [],
    this.reminder = const NoteReminder(dueAt: null),
    this.bounds,
    this.opacity = 1.0,
    this.popOnDesktop = true,
    this.showOnMobileWidget = true,
    this.isPinned = false,
    this.isAlwaysOnTop = false,
    this.isArchived = false,
    this.isDeleted = false,
    this.deletedAt,
  }) : id = id ?? _uuid.v4();

  factory Note.blank(String deviceId, {NoteType type = NoteType.note}) {
    final now = DateTime.now().toUtc();
    return Note(
      type: type,
      title: 'New note',
      body: '',
      colorHex: 'FFF4B8',
      createdAt: now,
      updatedAt: now,
      deviceId: deviceId,
      boardName: 'Personal',
      bounds: StickyBounds.defaults(),
      opacity: 1,
      popOnDesktop: true,
    );
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String?,
      type: NoteType.fromJson(json['type'] as String?),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      colorHex: json['colorHex'] as String? ?? 'FFF4B8',
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.tryParse(json['deletedAt'] as String)?.toUtc(),
      deviceId: json['deviceId'] as String? ?? '',
      revision: json['revision'] as int? ?? 1,
      boardName: json['boardName'] as String? ?? 'Personal',
      tags: ((json['tags'] as List?) ?? const [])
          .whereType<String>()
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(),
      checklist: ((json['checklist'] as List?) ?? const [])
          .whereType<Map>()
          .map(
              (item) => ChecklistItem.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      attachments: ((json['attachments'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) =>
              NoteAttachment.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      reminder: NoteReminder.fromJson(
        json['reminder'] == null
            ? null
            : Map<String, dynamic>.from(json['reminder'] as Map),
      ),
      bounds: StickyBounds.fromJson(
        json['bounds'] == null
            ? null
            : Map<String, dynamic>.from(json['bounds'] as Map),
      ),
      opacity: ((json['opacity'] as num?)?.toDouble() ?? 1).clamp(0.45, 1),
      isPinned: json['isPinned'] as bool? ?? false,
      popOnDesktop: json['popOnDesktop'] as bool? ?? true,
      showOnMobileWidget: json['showOnMobileWidget'] as bool? ?? true,
      isAlwaysOnTop: json['isAlwaysOnTop'] as bool? ?? false,
      isArchived: json['isArchived'] as bool? ?? false,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

  final String id;
  final NoteType type;
  final String title;
  final String body;
  final String colorHex;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String deviceId;
  final int revision;
  final String boardName;
  final List<String> tags;
  final List<ChecklistItem> checklist;
  final List<NoteAttachment> attachments;
  final NoteReminder reminder;
  final StickyBounds? bounds;
  final double opacity;
  final bool popOnDesktop;
  final bool showOnMobileWidget;
  final bool isPinned;
  final bool isAlwaysOnTop;
  final bool isArchived;
  final bool isDeleted;

  String get preview {
    final text = body.trim();
    if (text.isNotEmpty) return text;
    final firstOpenItem = checklist.firstWhereOrNull((item) => !item.done);
    return firstOpenItem?.text ?? '';
  }

  bool get hasReminder => reminder.isSet;
  bool get hasChecklist => checklist.isNotEmpty;
  bool get hasAttachments => attachments.isNotEmpty;
  bool get supportsBody => type == NoteType.note || type == NoteType.full;
  bool get supportsChecklist =>
      type == NoteType.checklist || type == NoteType.full;

  bool matchesQuery(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return title.toLowerCase().contains(normalized) ||
        body.toLowerCase().contains(normalized) ||
        type.label.toLowerCase().contains(normalized) ||
        boardName.toLowerCase().contains(normalized) ||
        tags.any((tag) => tag.toLowerCase().contains(normalized)) ||
        checklist.any((item) => item.text.toLowerCase().contains(normalized));
  }

  Note copyWith({
    NoteType? type,
    String? title,
    String? body,
    String? colorHex,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? deviceId,
    int? revision,
    String? boardName,
    List<String>? tags,
    List<ChecklistItem>? checklist,
    List<NoteAttachment>? attachments,
    NoteReminder? reminder,
    StickyBounds? bounds,
    double? opacity,
    bool? popOnDesktop,
    bool? showOnMobileWidget,
    bool? isPinned,
    bool? isAlwaysOnTop,
    bool? isArchived,
    bool? isDeleted,
  }) {
    return Note(
      id: id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      colorHex: colorHex ?? this.colorHex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      deviceId: deviceId ?? this.deviceId,
      revision: revision ?? this.revision,
      boardName: boardName ?? this.boardName,
      tags: tags ?? this.tags,
      checklist: checklist ?? this.checklist,
      attachments: attachments ?? this.attachments,
      reminder: reminder ?? this.reminder,
      bounds: bounds ?? this.bounds,
      opacity: opacity ?? this.opacity,
      popOnDesktop: popOnDesktop ?? this.popOnDesktop,
      showOnMobileWidget: showOnMobileWidget ?? this.showOnMobileWidget,
      isPinned: isPinned ?? this.isPinned,
      isAlwaysOnTop: isAlwaysOnTop ?? this.isAlwaysOnTop,
      isArchived: isArchived ?? this.isArchived,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'body': body,
        'colorHex': colorHex,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'deviceId': deviceId,
        'revision': revision,
        'boardName': boardName,
        'tags': tags,
        'checklist': checklist.map((item) => item.toJson()).toList(),
        'attachments': attachments.map((item) => item.toJson()).toList(),
        'reminder': reminder.toJson(),
        'bounds': bounds?.toJson(),
        'opacity': opacity,
        'popOnDesktop': popOnDesktop,
        'showOnMobileWidget': showOnMobileWidget,
        'isPinned': isPinned,
        'isAlwaysOnTop': isAlwaysOnTop,
        'isArchived': isArchived,
        'isDeleted': isDeleted,
      };
}
