import 'package:flutter/material.dart';

import '../models/note.dart';
import 'note_colors.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.selected,
    required this.onTap,
  });

  final Note note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = noteColor(note.colorHex);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : color,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    switch (note.type) {
                      NoteType.note => Icons.sticky_note_2_outlined,
                      NoteType.checklist => Icons.checklist,
                      NoteType.full => Icons.edit_note,
                    },
                    size: 16,
                    color: Colors.black87,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      note.title.isEmpty ? 'Untitled' : note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                    ),
                  ),
                  if (note.isPinned) const Icon(Icons.push_pin, size: 16),
                  if (note.hasReminder) const Icon(Icons.alarm, size: 16),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  note.preview,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(color: Colors.black87),
                ),
              ),
              if (note.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: note.tags.take(3).map((tag) {
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
