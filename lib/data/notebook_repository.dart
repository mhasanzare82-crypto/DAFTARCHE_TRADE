import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';

/// Single persistence boundary for notebook data.
/// Keeps the existing SharedPreferences keys to preserve user data.
class NotebookRepository {
  static const _notesKey = 'notebook_notes';
  static const _themesKey = 'notebook_themes';
  static const _foldersKey = 'notebook_folders';
  static const _fontsKey = 'notebook_custom_fonts';

  Future<List<Note>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString(_notesKey), Note.fromJson);
  }

  Future<List<NoteTheme>> loadThemes() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString(_themesKey), NoteTheme.fromJson);
  }

  Future<List<NoteFolder>> loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString(_foldersKey), NoteFolder.fromJson);
  }

  Future<Map<String, String>> loadCustomFonts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_fontsKey);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try { return Map<String, String>.from(jsonDecode(raw) as Map); }
    catch (_) { return <String, String>{}; }
  }

  Future<void> saveNotes(List<Note> values) => _save(_notesKey, values.map((e) => e.toJson()).toList());
  Future<void> saveThemes(List<NoteTheme> values) => _save(_themesKey, values.map((e) => e.toJson()).toList());
  Future<void> saveFolders(List<NoteFolder> values) => _save(_foldersKey, values.map((e) => e.toJson()).toList());
  Future<void> saveCustomFonts(Map<String, String> values) => _save(_fontsKey, values);

  Future<void> _save(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    final success = await prefs.setString(key, jsonEncode(value));
    if (!success) throw StateError('Unable to persist notebook data: $key');
  }

  List<T> _decodeList<T>(String? raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw == null || raw.isEmpty) return <T>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <T>[];
      return decoded.whereType<Map>().map((item) => fromJson(Map<String, dynamic>.from(item))).toList();
    } catch (_) { return <T>[]; }
  }
}
