import '../../domain/models/enums.dart';

/// Single authoritative utility for closed-evidence integrity rules.
///
/// Ensures strict adherence to:
/// 1. Only Closed observations can possess a linked media reference (`linkedMediaId`).
/// 2. Switching away from Closed or clearing a link immediately clears `linkedMediaId`
///    and removes any system-owned `Evid_ID: <id>` lines from notes.
/// 3. User notes and remarks are strictly preserved.
class ClosedEvidenceIntegrity {
  static String formatEvidId(String id) => 'Evid_ID: $id';

  /// Updates [currentNote] with a system-owned Evid_ID line for [newId].
  ///
  /// If a system-owned Evid_ID for [previousId] is present, only that line is replaced.
  /// User-owned notes and any manually entered text are strictly preserved.
  /// If [newId] is already present, no duplicate line is created.
  static String updateNoteWithEvidId({
    required String currentNote,
    required String newId,
    String? previousId,
  }) {
    final newLine = formatEvidId(newId);
    final prevLine = (previousId != null && previousId.isNotEmpty)
        ? formatEvidId(previousId)
        : null;

    if (currentNote.trim().isEmpty) {
      return newLine;
    }

    final lines = currentNote.split(RegExp(r'\r?\n'));

    // If previous system-owned line exists, replace only that exact line
    if (prevLine != null) {
      final prevIndex = lines.indexWhere((l) => l.trim() == prevLine);
      if (prevIndex != -1) {
        lines[prevIndex] = newLine;
        // Clean up any accidental duplicates of prevLine or newLine
        for (int i = lines.length - 1; i > prevIndex; i--) {
          if (lines[i].trim() == prevLine || lines[i].trim() == newLine) {
            lines.removeAt(i);
          }
        }
        return lines.join('\n');
      }
    }

    // If newLine is already present, do not duplicate
    if (lines.any((l) => l.trim() == newLine)) {
      return currentNote;
    }

    // Prepend system-owned line to existing notes
    return '$newLine\n$currentNote';
  }

  /// Removes the system-owned Evid_ID line corresponding to [linkedId] from [currentNote].
  ///
  /// User-owned notes and any non-matching Evid_ID text are strictly preserved.
  static String removeEvidIdFromNote({
    required String currentNote,
    required String linkedId,
  }) {
    if (linkedId.isEmpty) return currentNote;
    final target = formatEvidId(linkedId);
    final lines = currentNote.split(RegExp(r'\r?\n'));
    final index = lines.indexWhere((l) => l.trim() == target);
    if (index == -1) return currentNote;

    lines.removeAt(index);
    if (index == 0 && lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    if (lines.isEmpty) return '';
    return lines.join('\n');
  }

  /// Removes all system-owned Evid_ID lines and references from [currentNote].
  ///
  /// User-owned notes and any manually entered text are strictly preserved.
  static String removeAllEvidIdsFromNote(String currentNote) {
    if (currentNote.isEmpty) return currentNote;
    final lines = currentNote.split(RegExp(r'\r?\n'));
    lines.removeWhere((l) => RegExp(r'^\s*Evid_ID:\s*').hasMatch(l.trim()));
    final cleanedLines = lines
        .map((line) => line.replaceAll(RegExp(r'\s*Evid_ID:\s*\S+'), '').trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return cleanedLines.join('\n');
  }

  /// Single shared integrity rule that validates and aligns observation type,
  /// linkedMediaId, and note representation.
  ///
  /// Enforces:
  /// 1. If [observationType] is not [ObservationType.closed], [linkedMediaId] MUST be null,
  ///    and any system-owned Evid_ID lines in [note] MUST be removed.
  /// 2. If [observationType] is [ObservationType.closed] and [linkedMediaId] is null or empty,
  ///    [linkedMediaId] is null, and any system-owned Evid_ID lines in [note] are removed.
  /// 3. If [observationType] is [ObservationType.closed] and [linkedMediaId] is valid,
  ///    [linkedMediaId] is preserved, and the note is ensured to reference the linked media ID.
  static ({String? linkedMediaId, String? note}) enforceIntegrity({
    required ObservationType observationType,
    required String? linkedMediaId,
    required String? note,
  }) {
    final cleanNote = note?.trim();
    if (observationType != ObservationType.closed) {
      final strippedNote = cleanNote != null ? removeAllEvidIdsFromNote(cleanNote).trim() : null;
      return (
        linkedMediaId: null,
        note: (strippedNote != null && strippedNote.isNotEmpty) ? strippedNote : null,
      );
    }

    final cleanLinkedId = linkedMediaId?.trim();
    if (cleanLinkedId == null || cleanLinkedId.isEmpty) {
      final strippedNote = cleanNote != null ? removeAllEvidIdsFromNote(cleanNote).trim() : null;
      return (
        linkedMediaId: null,
        note: (strippedNote != null && strippedNote.isNotEmpty) ? strippedNote : null,
      );
    }

    final updatedNote = updateNoteWithEvidId(
      currentNote: cleanNote ?? '',
      newId: cleanLinkedId,
    ).trim();

    return (
      linkedMediaId: cleanLinkedId,
      note: updatedNote.isNotEmpty ? updatedNote : null,
    );
  }
}
