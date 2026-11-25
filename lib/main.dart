import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:dart_quill_delta/dart_quill_delta.dart' as delta;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/note.dart';
import 'data/notebook_repository.dart';
import 'screens/theme_dialogs.dart';
import 'screens/drawing_page.dart';

const String _quillNoteMarker = '__quill_note_v1__';
const String _legacyRichNoteMarker = '__rich_note_v1__';

List<Map<String, dynamic>> _decodeNoteBlocks(String body) {
  final value = body.startsWith(_legacyRichNoteMarker)
      ? body.substring(_legacyRichNoteMarker.length)
      : body;
  try {
    final decoded = jsonDecode(value);
    if (decoded is List) {
      return decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    }
  } catch (_) {}
  if (body.startsWith(_quillNoteMarker)) {
    try {
      final delta = jsonDecode(body.substring(_quillNoteMarker.length)) as List;
      return delta.map((raw) {
        final op = Map<String, dynamic>.from(raw as Map);
        final insert = op['insert'];
        if (insert is Map && insert['image'] is String) {
          return <String, dynamic>{'type': 'image', 'path': insert['image'] as String};
        }
        return <String, dynamic>{'type': 'text', 'text': insert is String ? insert : ''};
      }).toList();
    } catch (_) {}
  }
  return body.isEmpty ? <Map<String, dynamic>>[] : <Map<String, dynamic>>[{'type': 'text', 'text': body}];
}

String _notePlainText(String body) {
  if (body.startsWith(_quillNoteMarker)) {
    try {
      final delta = jsonDecode(body.substring(_quillNoteMarker.length)) as List;
      final document = quill.Document.fromJson(delta);
      return document.toPlainText().trim();
    } catch (_) {}
  }
  return _decodeNoteBlocks(body)
      .where((block) => block['type'] == 'text')
      .map((block) => block['text'] as String? ?? '')
      .join('\n')
      .trim();
}


ThemeData _buildAppTheme(String preset, String fontFamily) {
  final isWhite = preset == 'سفید';
  final isBlack = preset == 'سیاه';
  final isSilver = preset == 'نقره‌ای';
  final background = isWhite ? const Color(0xFFF9FAFB) : isBlack ? const Color(0xFF101114) : isSilver ? const Color(0xFFE1E4E8) : const Color(0xFF292D32);
  final surface = isWhite ? Colors.white : isBlack ? const Color(0xFF1A1C20) : isSilver ? const Color(0xFFF0F2F5) : const Color(0xFF363B41);
  final foreground = (isBlack || preset == 'دودی') ? const Color(0xFFF0F1F3) : const Color(0xFF202327);
  final primary = isWhite ? const Color(0xFF41464D) : isBlack ? const Color(0xFFB8BEC7) : isSilver ? const Color(0xFF68717C) : const Color(0xFFB7BEC7);
  final appBarBackground = isWhite ? const Color(0xFFF1F3F5) : isBlack ? const Color(0xFF08090B) : isSilver ? const Color(0xFFC8CDD4) : const Color(0xFF171A1E);
  final dark = isBlack || preset == 'دودی';
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily == 'system-default' ? null : fontFamily,
    colorScheme: ColorScheme.fromSeed(seedColor: primary, brightness: dark ? Brightness.dark : Brightness.light).copyWith(
      primary: primary,
      onPrimary: dark ? const Color(0xFF17191C) : Colors.white,
      secondary: isSilver ? const Color(0xFF929BA6) : const Color(0xFF9DA3AA),
      onSecondary: const Color(0xFF202327),
      surface: surface,
    ),
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(backgroundColor: appBarBackground, foregroundColor: foreground, elevation: 0, iconTheme: IconThemeData(color: foreground)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: primary, foregroundColor: dark ? const Color(0xFF17191C) : Colors.white, elevation: 5),
  );
  return base;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final encodedFont = await rootBundle.loadString('assets/fonts/Estedad.ttf.base64');
    final fontBytes = base64Decode(encodedFont);
    final loader = FontLoader('Estedad')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(fontBytes)));
    await loader.load();
  } catch (error, stackTrace) {
    debugPrint('Estedad font loading failed: $error\n$stackTrace');
  }
  runApp(const NotebookApp());
}
class NotebookApp extends StatefulWidget {
  const NotebookApp({super.key});
  @override
  State<NotebookApp> createState() => _NotebookAppState();
}

class _NotebookAppState extends State<NotebookApp> {
  String appFontFamily = 'Estedad';
  String appThemeName = 'دودی';
  final NotebookRepository repository = NotebookRepository();

  @override
  void initState() {
    super.initState();
    _loadAppFont();
    _loadAppTheme();
  }

  Future<void> _loadAppFont() async {
    final saved = await repository.loadAppFont();
    if (!mounted) return;
    final selected = (saved == null || saved == 'sans-serif' || saved == 'sans_serif' || saved == 'system-default') ? 'Estedad' : saved;
    setState(() => appFontFamily = selected);
    if (saved != selected) await repository.saveAppFont(selected);
  }

  Future<void> _loadAppTheme() async {
    final saved = await repository.loadAppTheme();
    if (!mounted) return;
    setState(() => appThemeName = ['سفید', 'سیاه', 'دودی', 'نقره‌ای'].contains(saved) ? saved : 'دودی');
  }

  Future<void> _setAppTheme(String theme) async {
    setState(() => appThemeName = theme);
    await repository.saveAppTheme(theme);
  }

  Future<void> _setAppFont(String family) async {
    setState(() => appFontFamily = family);
    await repository.saveAppFont(family);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'دفترچه ترید',
    theme: _buildAppTheme(appThemeName, appFontFamily),
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      quill.FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: const [Locale('fa'), Locale('en')],
    home: NotesPage(
      appFontFamily: appFontFamily,
      appThemeName: appThemeName,
      onAppFontChanged: _setAppFont,
      onAppThemeChanged: _setAppTheme,
    ),
  );
}

Future<void> _ignoreAppFontChange(String _) async {}

class NotesPage extends StatefulWidget {
  final String appFontFamily;
  final String appThemeName;
  final Future<void> Function(String) onAppFontChanged;
  final Future<void> Function(String) onAppThemeChanged;
  const NotesPage({super.key, this.appFontFamily = 'Estedad', this.appThemeName = 'دودی', this.onAppFontChanged = _ignoreAppFontChange, this.onAppThemeChanged = _ignoreAppFontChange});
  @override
  State<NotesPage> createState() => _NotesPageState();
}
class _NotesPageState extends State<NotesPage> {
  final NotebookRepository repository = NotebookRepository();
  final notes=<Note>[];
  final themes=<NoteTheme>[];
  final folders=<NoteFolder>[];
  final search=TextEditingController();
  final AudioPlayer noteAudioPlayer = AudioPlayer();
  String? currentlyPlayingAudio;
  String? selectedFolderId;
  bool loading=true;
  bool showFullNoteCards = false;
  bool isBulkSelectionMode = false;
  final Set<String> selectedNoteIds = <String>{};
  final customFonts=<String, String>{};
  final randomThemeNames=<String>{};
  final textColorPalette=<int>[];
  static const defaultThemes=[NoteTheme('یاسی',0xFFEDE7F6),NoteTheme('آبی',0xFFE3F2FD),NoteTheme('سبز',0xFFE8F5E9),NoteTheme('صورتی',0xFFFCE4EC),NoteTheme('هلویی',0xFFFFEAD5)];

  @override
  void initState(){super.initState();search.addListener(()=>setState((){}));noteAudioPlayer.onPlayerComplete.listen((_){if(mounted)setState(()=>currentlyPlayingAudio=null);});_loadCardDisplayMode();load();}
  Future<void> _loadCardDisplayMode() async { final saved = await repository.loadFullNoteCards(); if (mounted) setState(() => showFullNoteCards = saved); }
  Future<void> _toggleCardDisplayMode() async { final next = !showFullNoteCards; setState(() => showFullNoteCards = next); try { await repository.saveFullNoteCards(next); } catch (error) { if (!mounted) return; setState(() => showFullNoteCards = !next); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ذخیره حالت نمایش انجام نشد: $error'))); } }
  Future<void> load() async {
    try {
      final loadedNotes = await repository.loadNotes();
      final loadedThemes = await repository.loadThemes();
      final loadedFolders = await repository.loadFolders();
      final loadedFonts = await repository.loadCustomFonts();
      final loadedRandomThemes = await repository.loadRandomThemeNames();
      final loadedTextColors = await repository.loadTextColorPalette();
      notes.addAll(loadedNotes);
      themes.addAll(loadedThemes);
      folders.addAll(loadedFolders);
      customFonts.addAll(loadedFonts);
      randomThemeNames.addAll(loadedRandomThemes);
      textColorPalette.addAll(loadedTextColors);
      for (final entry in customFonts.entries) {
        try {
          final file = File(entry.value);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final loader = FontLoader(entry.key)..addFont(Future.value(ByteData.sublistView(bytes)));
            await loader.load();
          }
        } catch (_) { /* An unavailable custom font must not block opening the notebook. */ }
      }
      if (themes.isEmpty) themes.addAll(defaultThemes);
      if (randomThemeNames.isEmpty) randomThemeNames.addAll(themes.map((t) => t.name));
      if (mounted) setState(() => loading = false);
      await persistThemes();
      await repository.saveRandomThemeNames(randomThemeNames.toList());
    } catch (error, stackTrace) {
      debugPrint('Notebook load failed: $error\\n$stackTrace');
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> persist() => repository.saveNotes(notes);
  Future<void> persistFolders() => repository.saveFolders(folders);
  Future<void> persistThemes() => repository.saveThemes(themes);

  List<NoteTheme> get _randomBackgroundThemes {
    final enabled = themes
        .where((theme) => randomThemeNames.contains(theme.name))
        .toList();
    return enabled.isNotEmpty ? enabled : (themes.isNotEmpty ? themes : defaultThemes);
  }

  Future<void> _applyRandomBackgroundPerNote() async {
    if (notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هنوز یادداشتی برای تغییر رنگ وجود ندارد.')),
      );
      return;
    }

    final pool = _randomBackgroundThemes;
    final random = Random();
    final updatedNotes = notes.map((note) {
      final selected = pool[random.nextInt(pool.length)];
      return Note(
        note.id,
        note.title,
        note.body,
        note.updated,
        List<String>.of(note.images),
        selected.backgroundColor,
        note.themeTextColor,
        note.themeFontFamily,
        note.folderId,
        List<String>.of(note.audios),
      );
    }).toList();

    try {
      await repository.saveNotes(updatedNotes);
      if (!mounted) return;
      setState(() {
        notes
          ..clear()
          ..addAll(updatedNotes);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برای هر یادداشت یک رنگ تصادفی انتخاب شد.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ذخیره رنگ‌های جدید انجام نشد: $error')),
        );
      }
    }
  }

  Future<void> _chooseOneBackgroundForAllNotes() async {
    if (notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هنوز یادداشتی برای تغییر رنگ وجود ندارد.')),
      );
      return;
    }

    final choices = themes.isNotEmpty ? List<NoteTheme>.of(themes) : defaultThemes;
    final selected = await showDialog<NoteTheme>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('انتخاب یک رنگ برای همه نوشته‌ها'),
          content: SizedBox(
            width: double.maxFinite,
            height: 360,
            child: ListView.separated(
              itemCount: choices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, index) {
                final theme = choices[index];
                final background = Color(theme.backgroundColor);
                final foreground = Color(theme.textColor);
                return Material(
                  color: background,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: CircleAvatar(
                      backgroundColor: foreground,
                      child: Icon(Icons.text_fields, color: background),
                    ),
                    title: Text(
                      theme.name,
                      style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'این رنگ پس‌زمینه برای همه یادداشت‌ها اعمال می‌شود',
                      style: TextStyle(color: foreground.withOpacity(.78), fontSize: 11),
                    ),
                    trailing: Icon(Icons.check_circle_outline, color: foreground),
                    onTap: () => Navigator.pop(dialogContext, theme),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;

    final updatedNotes = notes.map((note) => Note(
      note.id,
      note.title,
      note.body,
      note.updated,
      List<String>.of(note.images),
      selected.backgroundColor,
      note.themeTextColor,
      note.themeFontFamily,
      note.folderId,
      List<String>.of(note.audios),
    )).toList();

    try {
      await repository.saveNotes(updatedNotes);
      if (!mounted) return;
      setState(() {
        notes
          ..clear()
          ..addAll(updatedNotes);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('رنگ «${selected.name}» روی همه یادداشت‌ها اعمال شد.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ذخیره رنگ جدید انجام نشد: $error')),
        );
      }
    }
  }

  Future<void> _showNoteColorOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Wrap(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
                child: Text('روش تغییر رنگ نوشته‌ها', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              ListTile(
                leading: const Icon(Icons.shuffle_rounded),
                title: const Text('رنگ تصادفی برای هر نوشته'),
                subtitle: const Text('هر یادداشت یک رنگ مستقل دریافت می‌کند.'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _applyRandomBackgroundPerNote();
                },
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('انتخاب یک رنگ برای همه نوشته‌ها'),
                subtitle: const Text('یک رنگ از تم‌های موجود انتخاب کن.'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _chooseOneBackgroundForAllNotes();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> createFolder() async {
    final controller=TextEditingController();
    final name=await showDialog<String>(context:context,builder:(c)=>Directionality(textDirection:TextDirection.rtl,child:AlertDialog(
      title:const Text('ایجاد پوشه'),content:TextField(controller:controller,autofocus:true,maxLength:30,decoration:const InputDecoration(labelText:'نام پوشه',hintText:'مثلاً کار و پروژه‌ها')),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(c,controller.text.trim()),child:const Text('ایجاد'))])));
    controller.dispose();
    if(name==null||name.trim().isEmpty)return;
    final folder=NoteFolder(DateTime.now().microsecondsSinceEpoch.toString(),name.trim());
    setState((){folders.add(folder);selectedFolderId=folder.id;});
    await persistFolders();
  }
  Future<void> editFolder(NoteFolder folder) async {
    final controller = TextEditingController(text: folder.name);
    final name = await showDialog<String>(context: context, builder: (c) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('ویرایش پوشه'),
        content: TextField(controller: controller, autofocus: true, maxLength: 30, decoration: const InputDecoration(labelText: 'نام پوشه')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text('ذخیره')),
        ],
      ),
    ));
    controller.dispose();
    if (name == null || name.trim().isEmpty || name.trim() == folder.name) return;
    setState(() {
      final index = folders.indexWhere((f) => f.id == folder.id);
      if (index >= 0) folders[index] = NoteFolder(folder.id, name.trim(), isPinned: folder.isPinned);
    });
    await persistFolders();
  }

  Future<void> deleteFolder(NoteFolder folder) async {
    final confirmed = await showDialog<bool>(context: context, builder: (c) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('حذف پوشه؟'),
        content: Text('پوشه «${folder.name}» حذف می‌شود؛ یادداشت‌های داخل آن حذف نمی‌شوند و به بخش بدون پوشه منتقل می‌شوند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف پوشه')),
        ],
      ),
    ));
    if (confirmed != true) return;
    setState(() {
      folders.removeWhere((f) => f.id == folder.id);
      for (var i = 0; i < notes.length; i++) {
        final note = notes[i];
        if (note.folderId == folder.id) {
          notes[i] = Note(note.id, note.title, note.body, note.updated, note.images,
            note.themeColor, note.themeTextColor, note.themeFontFamily, null, note.audios);
        }
      }
      if (selectedFolderId == folder.id) selectedFolderId = null;
    });
    await persistFolders();
    await persist();
  }

  Future<void> manageFolders() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => FolderManagementPage(
          initialFolders: List<NoteFolder>.of(folders),
          onChanged: (updatedFolders, deletedIds) async {
            setState(() {
              folders
                ..clear()
                ..addAll(updatedFolders);
              if (selectedFolderId != null && deletedIds.contains(selectedFolderId)) {
                selectedFolderId = null;
              }
              if (deletedIds.isNotEmpty) {
                for (var i = 0; i < notes.length; i++) {
                  final note = notes[i];
                  if (deletedIds.contains(note.folderId)) {
                    notes[i] = Note(note.id, note.title, note.body, note.updated,
                      List<String>.of(note.images), note.themeColor, note.themeTextColor,
                      note.themeFontFamily, null, List<String>.of(note.audios));
                  }
                }
              }
            });
            await persistFolders();
            if (deletedIds.isNotEmpty) await persist();
          },
          onSelectFolder: (folderId) {
            setState(() => selectedFolderId = folderId);
          },
        ),
      ),
    );
  }

  Future<void> moveNote(Note note) async {
    final destination=await showDialog<String?>(context:context,builder:(c)=>Directionality(textDirection:TextDirection.rtl,child:AlertDialog(
      title:const Text('انتقال یادداشت به پوشه'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        ListTile(leading:const Icon(Icons.inbox_outlined),title:const Text('بدون پوشه'),onTap:()=>Navigator.pop(c,'')),
        ...folders.map((folder)=>ListTile(leading:const Icon(Icons.folder_outlined),title:Text(folder.name),onTap:()=>Navigator.pop(c,folder.id))),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('انصراف'))],
    )));
    if(destination==null)return;
    final id=destination.isEmpty?null:destination;
    setState((){final i=notes.indexWhere((n)=>n.id==note.id);if(i>=0){final n=notes[i];notes[i]=Note(n.id,n.title,n.body,n.updated,List.of(n.images),n.themeColor,n.themeTextColor,n.themeFontFamily,id,List.of(n.audios));}});
    await persist();
  }
  Future<void> manageThemes() async {
    final result = await showDialog<ThemeManagerResult>(
      context: context,
      builder: (context) => ThemeManagerDialog(
        initialThemes: List.of(themes),
        appFontFamily: widget.appFontFamily,
        appThemeName: widget.appThemeName,
        customFonts: Map<String, String>.of(customFonts),
        initialRandomThemeNames: randomThemeNames.toList(),
        initialTextColorPalette: List<int>.of(textColorPalette),
      ),
    );
    if (result == null) return;
    setState(() {
      themes..clear()..addAll(result.themes);
      randomThemeNames..clear()..addAll(result.randomThemeNames);
      textColorPalette..clear()..addAll(result.textColorPalette);
      customFonts..clear()..addAll(result.customFonts);
    });
    await repository.saveCustomFonts(customFonts);
    await persistThemes();
    await repository.saveRandomThemeNames(randomThemeNames.toList());
    await repository.saveTextColorPalette(textColorPalette);
    await widget.onAppFontChanged(result.appFontFamily);
    await widget.onAppThemeChanged(result.appThemeName);
  }
  Future<void> addCustomFont() async {
    final picked=await FilePicker.pickFiles(type:FileType.custom,allowedExtensions:['ttf','otf']);
    if(picked.isEmpty)return;
    final file=picked.first;
    final filePath = file.path;
    if (filePath == null || filePath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('مسیر فایل فونت قابل دسترسی نیست.')),
        );
      }
      return;
    }
    final bytes = await File(filePath).readAsBytes();
    final parts=file.name.split('.');
    final original=parts.length>1?parts.sublist(0,parts.length-1).join('.'):file.name;
    final family='custom_'+original.replaceAll(RegExp(r'[^A-Za-z0-9_]+'),'_')+'_'+DateTime.now().millisecondsSinceEpoch.toString();
    final dir=await getApplicationDocumentsDirectory();
    final folder=Directory(dir.path+'/custom_fonts');
    if(!await folder.exists())await folder.create(recursive:true);
    final ext=(file.extension??'ttf').toLowerCase();
    final saved=File(folder.path+'/'+family+'.'+ext);
    await saved.writeAsBytes(bytes,flush:true);
    try {
      final loader=FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    } catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('بارگذاری این فونت ممکن نشد. فایل TTF یا OTF معتبر انتخاب کن.')));
      return;
    }
    customFonts[family]=saved.path;
    await repository.saveCustomFonts(customFonts);
    if(mounted){setState((){});ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('فونت «'+original+'» اضافه شد. اکنون نام آن را در بخش فونت تم انتخاب کن.')));}
  }
  List<Note> get filtered {
    final q = search.text.trim().toLowerCase();

    // The main "همه" view is intentionally the unfiled view:
    // notes assigned to a folder appear only inside that folder.
    final list = notes.where((note) {
      final matchesFolder = selectedFolderId == null
          ? note.folderId == null
          : note.folderId == selectedFolderId;
      final matchesSearch = note.title.toLowerCase().contains(q) ||
          _notePlainText(note.body).toLowerCase().contains(q);
      return matchesFolder && matchesSearch;
    }).toList();

    list.sort((a, b) => b.updated.compareTo(a.updated));
    return list;
  }

  // During a search, show the exact original line(s) containing the query.
  String _searchPreviewLines(String source, String query) {
    final q = query.trim();
    if (q.isEmpty) return source;
    final matchingLines = source
        .split('\n')
        .where((line) => line.toLowerCase().contains(q.toLowerCase()))
        .take(3)
        .toList();
    return matchingLines.isEmpty ? source : matchingLines.join('\n');
  }

  TextSpan _highlightSearchText(String value, String query, TextStyle baseStyle) {
    final q = query.trim();
    if (q.isEmpty) return TextSpan(text: value, style: baseStyle);
    final expression = RegExp(RegExp.escape(q), caseSensitive: false);
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in expression.allMatches(value)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, match.start)));
      }
      spans.add(TextSpan(
        text: value.substring(match.start, match.end),
        style: baseStyle.copyWith(
          color: const Color(0xFF5B3FA3),
          fontWeight: FontWeight.bold,
          backgroundColor: const Color(0xFFE6DDF8),        ),
      ));
      cursor = match.end;
    }
    if (cursor < value.length) spans.add(TextSpan(text: value.substring(cursor)));
    return TextSpan(style: baseStyle, children: spans);
  }
  Future<void> edit([Note? note, String? searchTerm, int initialMatch = 0]) async {
    final availableThemes = themes.where((theme) => randomThemeNames.contains(theme.name)).toList();
    final themePool = availableThemes.isNotEmpty ? availableThemes : (themes.isEmpty ? defaultThemes : themes);
    final selected=note==null?themePool[Random().nextInt(themePool.length)]:NoteTheme('فعلی',note.themeColor,note.themeTextColor,note.themeFontFamily);
    final query = searchTerm?.trim() ?? '';
    final searchNotes = query.isEmpty ? <Note>[] : (notes.where((n) => _notePlainText(n.body).toLowerCase().contains(query.toLowerCase())).toList()..sort((a,b)=>b.updated.compareTo(a.updated)));
    final searchNoteIndex = searchNotes.indexWhere((n) => n.id == note?.id);
    final result=await Navigator.push<Note>(context,MaterialPageRoute(builder:(_)=>EditorPage(
      note:note,themes:themes,customFonts:customFonts.keys.toList(),initialTheme:selected,
      existingNotes: List<Note>.of(notes),
      initialFolderId:note?.folderId??selectedFolderId,initialSearchTerm:query.isEmpty?null:query,
      searchNotes:searchNotes,initialSearchNoteIndex:searchNoteIndex<0?0:searchNoteIndex,
      initialSearchMatch:initialMatch,
      onSearchNavigate: (updated, targetNoteIndex, targetMatch) async {
        if (updated != null) {
          final i = notes.indexWhere((n) => n.id == updated.id);
          if (i < 0) { notes.add(updated); } else { notes[i] = updated; }
          await persist();
        }
        if (!mounted || targetNoteIndex < 0 || targetNoteIndex >= searchNotes.length) return;
        final target = notes.firstWhere((n) => n.id == searchNotes[targetNoteIndex].id, orElse: () => searchNotes[targetNoteIndex]);
        Navigator.pop(context);
        await Future<void>.delayed(Duration.zero);
        if (mounted) await edit(target, query, targetMatch);
      },
    )));
    if(result==null)return;
    setState(() { final i=notes.indexWhere((n)=>n.id==result.id); if(i<0){notes.add(result);}else{notes[i]=result;} });
    await persist();
  }
  Future<void> remove(Note n) async {
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:const Text('حذف یادداشت؟'),content:const Text('این یادداشت حذف خواهد شد.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('حذف'))]));
    if(yes==true){setState(()=>notes.removeWhere((x)=>x.id==n.id));await persist();}
  }

  String _xmlEscape(String value) => value.replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;').replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;').replaceAll("'", '&apos;');

  List<Map<String, dynamic>> _deltaForNote(Note note) {
    const marker = '__quill_note_v1__';
    if (note.body.startsWith(marker)) {
      try { return (jsonDecode(note.body.substring(marker.length)) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(); } catch (_) {}
    }
    final legacy = _decodeNoteBlocks(note.body);
    final ops = <Map<String, dynamic>>[];
    for (final item in legacy) {
      if (item['type'] == 'image') { ops.add({'insert': {'image': item['path']}}); ops.add({'insert': '\n'}); }
      else { ops.add({'insert': (item['text'] as String? ?? '') + '\n'}); }
    }
    return ops;
  }

  String _docxRun(String value, Map attributes) {
    if (value.isEmpty) return '';
    final props = StringBuffer();
    if (attributes['bold'] == true) props.write('<w:b/>');
    if (attributes['italic'] == true) props.write('<w:i/>');
    if (attributes['underline'] == true) props.write('<w:u w:val="single"/>');
    if (attributes['strike'] == true) props.write('<w:strike/>');
    final color = attributes['color'];
    if (color is String && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(color)) props.write('<w:color w:val="$color"/>');
    final background = attributes['background'];
    if (background is String && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(background)) props.write('<w:shd w:fill="$background"/>');
    final size = double.tryParse('${attributes['size'] ?? ''}');
    if (size != null) { final half = (size * 2).round(); props.write('<w:sz w:val="$half"/><w:szCs w:val="$half"/>'); }
    final font = attributes['font'];
    if (font is String && font.isNotEmpty) props.write('<w:rFonts w:ascii="${_xmlEscape(font)}" w:hAnsi="${_xmlEscape(font)}" w:eastAsia="${_xmlEscape(font)}"/>');
    final rPr = props.isEmpty ? '' : '<w:rPr>${props.toString()}</w:rPr>';
    return '<w:r>$rPr<w:t xml:space="preserve">${_xmlEscape(value)}</w:t></w:r>';
  }

  String _docxImageDrawing(String relationshipId) => '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="4572000" cy="3048000"/><wp:docPr id="1" name="Embedded image"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="0" name="image"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="$relationshipId"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="4572000" cy="3048000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';

  Future<Uint8List> _buildDocx(List<Note> selected) async {
    final archive = Archive();
    final media = <String, List<int>>{};
    final relationships = <String>[];
    var imageIndex = 0;
    final paragraphs = <String>[];
    for (final note in selected) {
      paragraphs.add('<w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr>${_docxRun(note.title.isEmpty ? 'بدون عنوان' : note.title, {'bold': true, 'size': 20})}</w:p>');
      var runs = StringBuffer();
      var paragraphAttributes = <String, dynamic>{};
      void flushParagraph() {
        final pPr = StringBuffer();
        final header = paragraphAttributes['header'];
        if (header == 1 || header == 2 || header == 3) pPr.write('<w:pStyle w:val="Heading$header"/>');
        final align = paragraphAttributes['align'];
        if (align == 'center' || align == 'right' || align == 'left' || align == 'justify') pPr.write('<w:jc w:val="$align"/>');
        final listType = paragraphAttributes['list'];
        if (listType == 'bullet' || listType == 'ordered') pPr.write('<w:numPr><w:ilvl w:val="0"/><w:numId w:val="${listType == 'ordered' ? 2 : 1}"/></w:numPr>');
        paragraphs.add('<w:p>${pPr.isEmpty ? '' : '<w:pPr>${pPr.toString()}</w:pPr>'}${runs.toString()}</w:p>');
        runs = StringBuffer();
        paragraphAttributes = <String, dynamic>{};
      }
      for (final operation in _deltaForNote(note)) {
        final insert = operation['insert'];
        final attrs = operation['attributes'] is Map ? Map<String, dynamic>.from(operation['attributes'] as Map) : <String, dynamic>{};
        if (insert is String) {
          paragraphAttributes.addAll(attrs);
          final pieces = insert.split('\n');
          for (var i = 0; i < pieces.length; i++) {
            if (pieces[i].isNotEmpty) runs.write(_docxRun(pieces[i], attrs));
            if (i < pieces.length - 1) flushParagraph();
          }
        } else if (insert is Map && insert['image'] is String) {
          final path = insert['image'] as String;
          final file = File(path);
          if (await file.exists()) {
            final ext = path.toLowerCase().endsWith('.png') ? 'png' : path.toLowerCase().endsWith('.gif') ? 'gif' : 'jpg';
            final name = 'image${++imageIndex}.$ext';
            media['word/media/$name'] = await file.readAsBytes();
            final rid = 'rIdImage$imageIndex';
            relationships.add('<Relationship Id="$rid" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/$name"/>');
            runs.write(_docxImageDrawing(rid));
          }
        }
      }
      if (runs.isNotEmpty) flushParagraph();
      paragraphs.add('<w:p/>');
    }
    for (final entry in media.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>${paragraphs.join()}<w:sectPr/></w:body></w:document>';
    final contentTypes = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="jpg" ContentType="image/jpeg"/><Default Extension="png" ContentType="image/png"/><Default Extension="gif" ContentType="image/gif"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>';
    final rootRels = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>';
    relationships.add('<Relationship Id="rIdNumbering" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>');
    final docRels = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${relationships.join()}</Relationships>';
    final numbering = '<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="singleLevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/><w:lvlJc w:val="right"/><w:pPr><w:tabs><w:tab w:val="num" w:pos="720"/></w:tabs><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl></w:abstractNum><w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="singleLevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/><w:lvlJc w:val="right"/><w:pPr><w:tabs><w:tab w:val="num" w:pos="720"/></w:tabs><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl></w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num><w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num></w:numbering>';
    archive
      ..addFile(ArchiveFile('[Content_Types].xml', contentTypes.length, utf8.encode(contentTypes)))
      ..addFile(ArchiveFile('_rels/.rels', rootRels.length, utf8.encode(rootRels)))
      ..addFile(ArchiveFile('word/_rels/document.xml.rels', docRels.length, utf8.encode(docRels)))
      ..addFile(ArchiveFile('word/numbering.xml', numbering.length, utf8.encode(numbering)))
      ..addFile(ArchiveFile('word/document.xml', document.length, utf8.encode(document)));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<void> exportDocx(List<Note> selected) async {
    if (selected.isEmpty) return;
    final bytes = await _buildDocx(selected);
    final name = selected.length == 1
        ? '${(selected.first.title.isEmpty ? 'note' : selected.first.title).replaceAll(RegExp(r'[^\w\-آ-ی]'), '_')}.docx'
        : 'notebook_export.docx';
    try {
      await FilePicker.saveFile(fileName: name, bytes: bytes);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ذخیره فایل Word انجام نشد: $e')));
    }
  }

  Future<Note?> _noteFromDocx(PlatformFile file) async {
    final bytes = await file.readAsBytes();
    final zip = ZipDecoder().decodeBytes(bytes, verify: true, throwOnError: true);
    final documentFile = zip.findFile('word/document.xml');
    if (documentFile == null) return null;
    final xml = XmlDocument.parse(utf8.decode(documentFile.readBytes() ?? Uint8List(0), allowMalformed: true));
    final relsFile = zip.findFile('word/_rels/document.xml.rels');
    final relationships = <String, String>{};
    if (relsFile != null) {
      final rels = XmlDocument.parse(utf8.decode(relsFile.readBytes() ?? Uint8List(0), allowMalformed: true));
      for (final rel in rels.descendants.whereType<XmlElement>().where((e) => e.name.local == 'Relationship')) {
        final id = rel.attributes.where((a) => a.name.local == 'Id').map((a) => a.value).firstOrNull;
        final target = rel.attributes.where((a) => a.name.local == 'Target').map((a) => a.value).firstOrNull;
        if (id != null && target != null) relationships[id] = target;
      }
    }
    final numberingFormats = <String, String>{};
    final numberingFile = zip.findFile('word/numbering.xml');
    if (numberingFile != null) {
      final numberingXml = XmlDocument.parse(utf8.decode(numberingFile.readBytes() ?? Uint8List(0), allowMalformed: true));
      final abstractFormats = <String, String>{};
      for (final item in numberingXml.descendants.whereType<XmlElement>().where((e) => e.name.local == 'abstractNum')) {
        final abstractId = item.attributes.where((a) => a.name.local == 'abstractNumId').map((a) => a.value).firstOrNull;
        final format = item.descendants.whereType<XmlElement>().where((e) => e.name.local == 'numFmt').firstOrNull?.attributes.where((a) => a.name.local == 'val').map((a) => a.value).firstOrNull;
        if (abstractId != null && format != null) abstractFormats[abstractId] = format;
      }
      for (final item in numberingXml.descendants.whereType<XmlElement>().where((e) => e.name.local == 'num')) {
        final numId = item.attributes.where((a) => a.name.local == 'numId').map((a) => a.value).firstOrNull;
        final abstractId = item.descendants.whereType<XmlElement>().where((e) => e.name.local == 'abstractNumId').firstOrNull?.attributes.where((a) => a.name.local == 'val').map((a) => a.value).firstOrNull;
        if (numId != null && abstractId != null && abstractFormats.containsKey(abstractId)) numberingFormats[numId] = abstractFormats[abstractId]!;
      }
    }
    final imageDirRoot = await getApplicationDocumentsDirectory();
    final imageDir = Directory('${imageDirRoot.path}/notebook_images');
    if (!await imageDir.exists()) await imageDir.create(recursive: true);
    final operations = <Map<String, dynamic>>[];
    final imagePaths = <String>[];
    final paragraphs = xml.descendants.whereType<XmlElement>().where((e) => e.name.local == 'p').toList();
    // Preserve every paragraph as content; derive the note title from the filename.
    for (final paragraph in paragraphs) {
      final pPr = paragraph.children.whereType<XmlElement>().where((e) => e.name.local == 'pPr').firstOrNull;
      final lineAttrs = <String, dynamic>{};
      if (pPr != null) {
        final style = pPr.descendants.whereType<XmlElement>().where((e) => e.name.local == 'pStyle').firstOrNull;
        final styleVal = style?.attributes.where((a) => a.name.local == 'val').map((a) => a.value).firstOrNull ?? '';
        final heading = RegExp(r'Heading([1-3])', caseSensitive: false).firstMatch(styleVal);
        if (heading != null) lineAttrs['header'] = int.parse(heading.group(1)!);
        final jc = pPr.descendants.whereType<XmlElement>().where((e) => e.name.local == 'jc').firstOrNull;
        final align = jc?.attributes.where((a) => a.name.local == 'val').map((a) => a.value).firstOrNull;
        if (align != null) lineAttrs['align'] = align;
        final numId = pPr.descendants.whereType<XmlElement>().where((e) => e.name.local == 'numId').firstOrNull?.attributes.where((a) => a.name.local == 'val').map((a) => a.value).firstOrNull;
        if (numId != null) { final format = numberingFormats[numId]; lineAttrs['list'] = format == null || format == 'bullet' ? 'bullet' : 'ordered'; }
      }
      for (final run in paragraph.descendants.whereType<XmlElement>().where((e) => e.name.local == 'r')) {
        final rPr = run.children.whereType<XmlElement>().where((e) => e.name.local == 'rPr').firstOrNull;
        final attrs = <String, dynamic>{};
        if (rPr != null) {
          if (rPr.descendants.whereType<XmlElement>().any((e) => e.name.local == 'b')) attrs['bold'] = true;
          if (rPr.descendants.whereType<XmlElement>().any((e) => e.name.local == 'i')) attrs['italic'] = true;
          if (rPr.descendants.whereType<XmlElement>().any((e) => e.name.local == 'u')) attrs['underline'] = true;
          if (rPr.descendants.whereType<XmlElement>().any((e) => e.name.local == 'strike')) attrs['strike'] = true;
          final color = rPr.descendants.whereType<XmlElement>().where((e) => e.name.local == 'color').firstOrNull;
          final colorValue = color?.attributes.where((a) => a.name.local == 'val').map((a) => a.value).firstOrNull;
          if (colorValue != null && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(colorValue)) attrs['color'] = colorValue;
          final shade = rPr.descendants.whereType<XmlElement>().where((e) => e.name.local == 'shd').firstOrNull;
          final shadeValue = shade?.attributes.where((a) => a.name.local == 'fill').map((a) => a.value).firstOrNull;
          if (shadeValue != null && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(shadeValue)) attrs['background'] = shadeValue;
          final size = rPr.descendants.whereType<XmlElement>().where((e) => e.name.local == 'sz').firstOrNull;
          final sizeValue = size?.attributes.where((a) => a.name.local == 'val').map((a) => a.value).firstOrNull;
          if (sizeValue != null) { final parsed = int.tryParse(sizeValue); if (parsed != null) attrs['size'] = (parsed / 2).toString(); }
          final fonts = rPr.descendants.whereType<XmlElement>().where((e) => e.name.local == 'rFonts').firstOrNull;
          final fontValue = fonts?.attributes.where((a) => a.name.local == 'ascii').map((a) => a.value).firstOrNull;
          if (fontValue != null) attrs['font'] = fontValue;
        }
        for (final textElement in run.descendants.whereType<XmlElement>().where((e) => e.name.local == 't')) {
          if (textElement.innerText.isNotEmpty) operations.add({'insert': textElement.innerText, if (attrs.isNotEmpty) 'attributes': attrs});
        }
        for (final blip in run.descendants.whereType<XmlElement>().where((e) => e.name.local == 'blip')) {
          final rid = blip.attributes.where((a) => a.name.local == 'embed').map((a) => a.value).firstOrNull;
          final target = rid == null ? null : relationships[rid];
          if (target == null) continue;
          final resolved = Uri.parse('word/document.xml').resolve(target).path;
          final normalized = resolved.replaceAll('\\', '/').split('/').fold<String>('', (acc, part) {
            if (part.isEmpty || part == '.') return acc;
            if (part == '..') return acc.contains('/') ? acc.substring(0, acc.lastIndexOf('/')) : '';
            return acc.isEmpty ? part : '$acc/$part';
          });
          final mediaFile = zip.findFile(normalized);
          if (mediaFile == null) continue;
          final ext = normalized.contains('.') ? normalized.substring(normalized.lastIndexOf('.')) : '.png';
          final path = '${imageDir.path}/imported_${DateTime.now().microsecondsSinceEpoch}_${imagePaths.length}$ext';
          final imageBytes = mediaFile.readBytes();
          if (imageBytes == null || imageBytes.isEmpty) continue;
          await File(path).writeAsBytes(imageBytes);
          imagePaths.add(path);
          operations.add({'insert': {'image': path}});
        }
      }
      operations.add({'insert': '\n', if (lineAttrs.isNotEmpty) 'attributes': lineAttrs});
    }
    if (operations.isEmpty) operations.add({'insert': '\n'});
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final title = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return Note(id, title, '__quill_note_v1__${jsonEncode(operations)}', DateTime.now(), imagePaths);
  }

  Future<Note> _noteFromTxt(PlatformFile file) async {
    final bytes = await file.readAsBytes();
    final text = utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', '');
    final normalizedText = text.isEmpty || text.endsWith('\n') ? text : '$text\n';
    final operations = <Map<String, dynamic>>[{'insert': normalizedText.isEmpty ? '\n' : normalizedText}];
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final title = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return Note(id, title, '__quill_note_v1__${jsonEncode(operations)}', DateTime.now(), <String>[]);
  }

  Future<void> importDocx() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['docx', 'txt']);
      if (files.isEmpty) return;
      final imported = <Note>[];
      final failures = <String>[];
      for (final file in files) {
        try {
          final extension = (file.extension ?? file.name.split('.').last).toLowerCase();
          final Note? note = extension == 'txt' ? await _noteFromTxt(file) : extension == 'docx' ? await _noteFromDocx(file) : null;
          if (note != null) { imported.add(note); } else { failures.add(file.name); }
        } catch (error) { debugPrint('File import failed for ${file.name}: $error'); failures.add(file.name); }
      }
      if (imported.isNotEmpty) { setState(() => notes.addAll(imported)); await persist(); }
      if (mounted) {
        final message = failures.isEmpty ? '${imported.length} فایل با موفقیت به یادداشت تبدیل شد' : '${imported.length} فایل وارد شد؛ ${failures.length} فایل ناموفق بود: ${failures.take(2).join('، ')}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      debugPrint('File import selection failed: $error');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ورود فایل‌ها انجام نشد: $error')));
    }
  }

  Future<void> createBackup() async {
    try {
      final imageData = <String, String>{};
      for (final note in notes) {
        final paths = <String>{...note.images, ..._decodeNoteBlocks(note.body)
            .where((b) => b['type'] == 'image').map((b) => b['path'] as String),
          if (note.body.startsWith(_quillNoteMarker)) ...((jsonDecode(note.body.substring(_quillNoteMarker.length)) as List)
            .whereType<Map>().map((op) => op['insert']).whereType<Map>()
            .map((insert) => insert['image']).whereType<String>().where((path) => !path.startsWith('http')))};
        for (final path in paths) {
          final file = File(path);
          if (await file.exists()) imageData[path] = base64Encode(await file.readAsBytes());
        }
      }
      final backup = jsonEncode({
        'format': 'persian_notebook_backup', 'version': 1,
        'createdAt': DateTime.now().toIso8601String(),
        'notes': notes.map((n) => n.toJson()).toList(),
        'folders': folders.map((f) => f.toJson()).toList(),
        'themes': themes.map((t) => t.toJson()).toList(),
        'images': imageData,
      });
      await FilePicker.saveFile(fileName: 'notebook_backup.json',
          bytes: Uint8List.fromList(utf8.encode(backup)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ساخت نسخه پشتیبان ناموفق بود: $e')));
    }
  }

  Future<void> restoreBackup() async {
    try {
      final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('بازیابی نسخه پشتیبان؟'),
        content: const Text('یادداشت‌ها، پوشه‌ها و تم‌های فعلی با اطلاعات فایل پشتیبان جایگزین می‌شوند.'),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ادامه'))],
      ));
      if (confirmed != true) return;
      final file = await FilePicker.pickFile(type: FileType.custom,
          allowedExtensions: ['json']);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (data['format'] != 'persian_notebook_backup' || data['version'] != 1) {
        throw const FormatException('فرمت فایل پشتیبان معتبر نیست');
      }
      final dir = await getApplicationDocumentsDirectory();
      final imageDir = Directory('${dir.path}/notebook_images');
      if (!await imageDir.exists()) await imageDir.create(recursive: true);
      final restoredPaths = <String, String>{};
      final images = Map<String, dynamic>.from(data['images'] ?? {});
      for (final entry in images.entries) {
        final oldPath = entry.key;
        final extension = oldPath.contains('.') ? oldPath.substring(oldPath.lastIndexOf('.')) : '.jpg';
        final newPath = '${imageDir.path}/restored_${DateTime.now().microsecondsSinceEpoch}_${restoredPaths.length}$extension';
        await File(newPath).writeAsBytes(base64Decode(entry.value as String));
        restoredPaths[oldPath] = newPath;
      }
      final restoredNotes = (data['notes'] as List).map((raw) {
        final n = Note.fromJson(Map<String, dynamic>.from(raw));
        var body = n.body;
        if (n.body.startsWith('__quill_note_v1__')) {
          final delta = (jsonDecode(n.body.substring('__quill_note_v1__'.length)) as List).map((rawOp) {
            final op = Map<String, dynamic>.from(rawOp as Map);
            if (op['insert'] is Map) {
              final insert = Map<String, dynamic>.from(op['insert'] as Map);
              final image = insert['image'];
              if (image is String && restoredPaths.containsKey(image)) {
                op['insert'] = {...insert, 'image': restoredPaths[image]};              }
            }
            return op;
          }).toList();
          body = '__quill_note_v1__${jsonEncode(delta)}';
        } else if (n.body.startsWith('__rich_note_v1__')) {
          final blocks = _decodeNoteBlocks(n.body).map((block) {
            if (block['type'] == 'image' && restoredPaths.containsKey(block['path'])) {
              return {...block, 'path': restoredPaths[block['path']]};
            }
            return block;
          }).toList();
          body = '__rich_note_v1__${jsonEncode(blocks)}';
        }
        return Note(n.id, n.title, body, n.updated,
          n.images.map((path) => restoredPaths[path] ?? path).toList(),
          n.themeColor, n.themeTextColor, n.themeFontFamily, n.folderId);
      }).toList();
      setState(() {
        notes..clear()..addAll(restoredNotes);
        folders..clear()..addAll((data['folders'] as List? ?? []).map((e) => NoteFolder.fromJson(Map<String, dynamic>.from(e))));
        themes..clear()..addAll((data['themes'] as List? ?? []).map((e) => NoteTheme.fromJson(Map<String, dynamic>.from(e))));
        if (themes.isEmpty) themes.addAll(defaultThemes);
        selectedFolderId = null;
      });
      await persist(); await persistFolders(); await persistThemes();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نسخه پشتیبان با موفقیت بازیابی شد')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('بازیابی نسخه پشتیبان ناموفق بود: $e')));
    }
  }

  Future<void> playNoteAudio(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فایل ویس پیدا نشد.')),
        );
      }
      return;
    }
    try {
      if (currentlyPlayingAudio == path && noteAudioPlayer.state == PlayerState.playing) {
        await noteAudioPlayer.pause();
        if (mounted) setState(() => currentlyPlayingAudio = null);
        return;
      }
      await noteAudioPlayer.stop();
      if (!mounted) return;
      setState(() => currentlyPlayingAudio = path);
      await noteAudioPlayer.play(DeviceFileSource(path));
    } catch (error) {
      if (mounted) {
        setState(() => currentlyPlayingAudio = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('پخش ویس ناموفق بود: $error')),
        );
      }
    }
  }

  Future<void> changeNoteTheme(Note note) async {
    final available = themes.isNotEmpty ? List<NoteTheme>.of(themes) : List<NoteTheme>.of(defaultThemes);
    final selected = await showDialog<NoteTheme>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('انتخاب تم این یادداشت'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: available.map((theme) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Color(theme.backgroundColor),
                    child: Icon(Icons.text_fields_rounded, color: Color(theme.textColor)),
                  ),
                  title: Text(theme.name, style: TextStyle(
                    color: Color(theme.textColor),
                    fontFamily: theme.fontFamily,
                  )),
                  subtitle: Text('پس‌زمینه و رنگ متن این تم'),
                  trailing: note.themeColor == theme.backgroundColor &&
                      note.themeTextColor == theme.textColor &&
                      note.themeFontFamily == theme.fontFamily
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                  onTap: () => Navigator.pop(dialogContext, theme),
                )).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final index = notes.indexWhere((item) => item.id == note.id);
    if (index < 0) return;
    setState(() {
      final current = notes[index];
      notes[index] = Note(
        current.id,
        current.title,
        current.body,
        DateTime.now(),
        List<String>.of(current.images),
        selected.backgroundColor,
        selected.textColor,
        selected.fontFamily,
        current.folderId,
        List<String>.of(current.audios),
      );
    });
    await persist();
  }

  void showNoteMenu(Note note) {
    showModalBottomSheet<void>(context: context, builder: (sheetContext) =>
      Directionality(textDirection: TextDirection.rtl, child: SafeArea(child: Wrap(children: [
        ListTile(leading: const Icon(Icons.palette_outlined),
          title: const Text('تغییر تم این یادداشت'),
          onTap: () { Navigator.pop(sheetContext); changeNoteTheme(note); }),
        ListTile(leading: const Icon(Icons.file_download_outlined),
          title: const Text('خروجی Word برای این یادداشت'),
          onTap: () { Navigator.pop(sheetContext); exportDocx([note]); }),
        ListTile(leading: const Icon(Icons.file_open_outlined),
          title: const Text('وارد کردن فایل Word'),
          onTap: () { Navigator.pop(sheetContext); importDocx(); }),
        ListTile(leading: const Icon(Icons.drive_file_move_outline),
          title: const Text('انتقال به پوشه'),
          onTap: () { Navigator.pop(sheetContext); moveNote(note); }),
        ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red),
          title: const Text('حذف یادداشت'),
          onTap: () { Navigator.pop(sheetContext); remove(note); }),
      ]))));
  }

  String date(DateTime d)=>d.year.toString()+'/'+d.month.toString().padLeft(2,'0')+'/'+d.day.toString().padLeft(2,'0');
  @override
  void dispose(){search.dispose();noteAudioPlayer.dispose();super.dispose();}
  @override
  Widget build(BuildContext context){
    final items=filtered;
    return Directionality(textDirection:TextDirection.rtl,child:Scaffold(
      appBar:AppBar(
        title: isBulkSelectionMode
            ? Text('${_selectedNotesInView(items).length} نوشته انتخاب شده')
            : null,
        leading: isBulkSelectionMode
            ? IconButton(tooltip: 'خروج از انتخاب گروهی', onPressed: _clearBulkSelection, icon: const Icon(Icons.close))
            : null,
        actions: isBulkSelectionMode ? [
          IconButton(
            tooltip: 'انتخاب همه نوشته‌های این بخش',
            onPressed: () => _toggleSelectAll(items),
            icon: Icon(items.isNotEmpty && items.every((n) => selectedNoteIds.contains(n.id))
                ? Icons.deselect : Icons.select_all),
          ),
          PopupMenuButton<String>(
            tooltip: 'عملیات گروهی',
            onSelected: (action) {
              if (action == 'delete') _deleteSelectedNotes(items);
              if (action == 'move') _moveSelectedNotes(items);
              if (action == 'export') _exportSelectedNotesSeparately(items);
              if (action == 'theme') _applyThemeToSelectedNotes(items);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('حذف گروهی'))),
              PopupMenuItem(value: 'move', child: ListTile(leading: Icon(Icons.drive_file_move_outline), title: Text('انتقال به پوشه'))),
              PopupMenuItem(value: 'export', child: ListTile(leading: Icon(Icons.file_download_outlined), title: Text('خروجی جداگانه DOCX'))),
              PopupMenuItem(value: 'theme', child: ListTile(leading: Icon(Icons.palette_outlined), title: Text('تغییر تم گروهی'))),
            ],
          ),
        ] : [
          IconButton(tooltip:showFullNoteCards?'نمایش خلاصه یادداشت‌ها':'نمایش کامل متن و تصاویر یادداشت‌ها',onPressed:_toggleCardDisplayMode,icon:Icon(showFullNoteCards?Icons.view_agenda_outlined:Icons.article_outlined)),
          IconButton(tooltip:'انتخاب روش تغییر رنگ یادداشت‌ها',onPressed:_showNoteColorOptions,icon:const Icon(Icons.palette_outlined)),
          PopupMenuButton<String>(tooltip:'ورود و خروجی فایل‌ها',onSelected:(value){if(value=='import')importDocx();if(value=='export')exportDocx(notes);if(value=='backup')createBackup();if(value=='restore')restoreBackup();},itemBuilder:(context)=>const [PopupMenuItem(value:'import',child:ListTile(leading:Icon(Icons.file_open),title:Text('ورود گروهی DOCX'))),PopupMenuItem(value:'export',child:ListTile(leading:Icon(Icons.file_download),title:Text('خروجی گروهی DOCX'))),PopupMenuDivider(),PopupMenuItem(value:'backup',child:ListTile(leading:Icon(Icons.backup_outlined),title:Text('ساخت فایل پشتیبان'))),PopupMenuItem(value:'restore',child:ListTile(leading:Icon(Icons.settings_backup_restore),title:Text('بازیابی فایل پشتیبان')))]),
          IconButton(tooltip:'تنظیمات و شخصی‌سازی',onPressed:manageThemes,icon:const Icon(Icons.settings_outlined)),
        ],
      ),
      floatingActionButton:FloatingActionButton.extended(onPressed:()=>edit(),icon:const Icon(Icons.edit_note_rounded),label:const Text('یادداشت جدید')),
      body:SafeArea(child:Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(20,8,20,18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          TextField(controller:search,decoration:InputDecoration(hintText:'جستجو در یادداشت‌ها...',filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:BorderSide.none))),
          const SizedBox(height:14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() { selectedFolderId = null; selectedNoteIds.clear(); isBulkSelectionMode = false; }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: selectedFolderId == null ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('همه'),
                  ),
                ),
              ),
              ...([...folders]..sort((a, b) => (b.isPinned ? 1 : 0).compareTo(a.isPinned ? 1 : 0))).map((folder) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() { selectedFolderId = folder.id; selectedNoteIds.clear(); isBulkSelectionMode = false; }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: selectedFolderId == folder.id ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(folder.name),
                  ),
                ),
              )),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: IconButton(
                  tooltip: 'مدیریت پوشه‌ها',
                  onPressed: manageFolders,
                  icon: const Icon(Icons.folder_open_outlined),
                ),
              ),
            ]),
          ),
          const SizedBox(height:16),


        ])),
        Expanded(child:loading?const Center(child:CircularProgressIndicator()):items.isEmpty
          ? (search.text.isNotEmpty
              ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('یادداشتی پیدا نشد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('عبارت دیگری را جستجو کن.'),
                ]))
              : const SizedBox.shrink())
          :ListView.separated(padding:const EdgeInsets.fromLTRB(20,0,20,100),itemCount:items.length,separatorBuilder:(_,__)=>const SizedBox(height:10),itemBuilder:(_,i){
            final n=items[i];
            final isSelected = selectedNoteIds.contains(n.id);
            return Card(
              elevation: isSelected ? 2 : 0,
              color: Color(n.themeColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: isSelected ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2) : BorderSide.none,
              ),
              child: InkWell(
                onLongPress: () => _toggleBulkSelection(n),
                onTap: () {
                  if (isBulkSelectionMode) {
                    _toggleBulkSelection(n);
                  } else {
                    edit(n,search.text.trim().isEmpty||!_notePlainText(n.body).toLowerCase().contains(search.text.trim().toLowerCase())?null:search.text.trim());
                  }
                },
                child: Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[
                if (isBulkSelectionMode)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked, color: Color(n.themeTextColor)),
                  ),
                Expanded(child:RichText(text:_highlightSearchText(n.title.isEmpty?'بدون عنوان':n.title,search.text,TextStyle(fontWeight:FontWeight.bold,fontSize:16,color:Color(n.themeTextColor),fontFamily:n.themeFontFamily)),maxLines:1,overflow:TextOverflow.ellipsis)),
                if (!isBulkSelectionMode) IconButton(tooltip:'گزینه‌های یادداشت',onPressed:()=>showNoteMenu(n),icon:const Icon(Icons.more_vert))
              ]),
              if(_notePlainText(n.body).isNotEmpty)RichText(
                text:_highlightSearchText(
                  showFullNoteCards ? _notePlainText(n.body) : _searchPreviewLines(_notePlainText(n.body),search.text),
                  search.text,
                  TextStyle(color:Color(n.themeTextColor),fontFamily:n.themeFontFamily),
                ),
                maxLines:showFullNoteCards ? null : 3,
                overflow:showFullNoteCards ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
              if(showFullNoteCards && n.images.isNotEmpty)
                Padding(
                  padding:const EdgeInsets.only(top:10),
                  child:Column(
                    crossAxisAlignment:CrossAxisAlignment.stretch,
                    children:[
                      for(final imagePath in n.images)
                        if(File(imagePath).existsSync())
                          Padding(
                            padding:const EdgeInsets.only(bottom:8),
                            child:ClipRRect(
                              borderRadius:BorderRadius.circular(10),
                              child:Image.file(File(imagePath),fit:BoxFit.contain),
                            ),
                          ),
                    ],
                  ),
                )
              else if(n.images.isNotEmpty)
                Padding(padding:const EdgeInsets.only(top:8),child:Text(n.images.length.toString()+' تصویر پیوست شده',style:TextStyle(color:Color(n.themeTextColor).withOpacity(.7),fontSize:12))),
              if(n.audios.isNotEmpty)Padding(
                padding:const EdgeInsets.only(top:8),
                child:Wrap(
                  spacing:6,
                  runSpacing:4,
                  children:[
                    for(var audioIndex=0;audioIndex<n.audios.length;audioIndex++)
                      ActionChip(
                        avatar:Icon(
                          currentlyPlayingAudio==n.audios[audioIndex]
                              ? Icons.volume_up_rounded
                              : Icons.play_arrow_rounded,
                          size:18,
                          color:Color(n.themeTextColor),
                        ),
                        label:Text('پخش ویس ${audioIndex+1}',style:TextStyle(color:Color(n.themeTextColor))),
                        onPressed:()=>playNoteAudio(n.audios[audioIndex]),
                        backgroundColor:Color(n.themeColor).withOpacity(.75),
                      ),
                  ],
                ),
              ),
              const SizedBox(height:8),Text(date(n.updated),style:TextStyle(fontSize:11,color:Color(n.themeTextColor).withOpacity(.65))),
            ]))));
          })),
      ])),
    ));
  }
}

class FolderManagementPage extends StatefulWidget {
  final List<NoteFolder> initialFolders;
  final Future<void> Function(List<NoteFolder>, List<String>) onChanged;
  final void Function(String?) onSelectFolder;
  const FolderManagementPage({
    super.key,
    required this.initialFolders,
    required this.onChanged,
    required this.onSelectFolder,
  });

  @override
  State<FolderManagementPage> createState() => _FolderManagementPageState();
}

class _FolderManagementPageState extends State<FolderManagementPage> {
  late List<NoteFolder> folders;

  @override
  void initState() {
    super.initState();
    folders = List<NoteFolder>.of(widget.initialFolders)
      ..sort((a, b) => (b.isPinned ? 1 : 0).compareTo(a.isPinned ? 1 : 0));
  }

  Future<String?> _askName({String? initialName}) async {
    final controller = TextEditingController(text: initialName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(initialName == null ? 'ایجاد پوشه' : 'تغییر نام پوشه'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 30,
            decoration: const InputDecoration(labelText: 'نام پوشه'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('ذخیره')),
          ],
        ),
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return null;
    return name.trim();
  }

  Future<void> _createFolder() async {
    final name = await _askName();
    if (name == null || !mounted) return;
    final folder = NoteFolder(DateTime.now().microsecondsSinceEpoch.toString(), name);
    setState(() => folders.add(folder));
    await widget.onChanged(List<NoteFolder>.of(folders), <String>[]);
  }

  Future<void> _renameFolder(NoteFolder folder) async {
    final name = await _askName(initialName: folder.name);
    if (name == null || name == folder.name || !mounted) return;
    setState(() {
      final index = folders.indexWhere((item) => item.id == folder.id);
      if (index >= 0) folders[index] = NoteFolder(folder.id, name, isPinned: folder.isPinned);
    });
    await widget.onChanged(List<NoteFolder>.of(folders), <String>[]);
  }

  Future<void> _togglePin(NoteFolder folder) async {
    setState(() {
      final index = folders.indexWhere((item) => item.id == folder.id);
      if (index >= 0) {
        folders[index] = NoteFolder(folder.id, folder.name, isPinned: !folder.isPinned);
        folders.sort((a, b) => (b.isPinned ? 1 : 0).compareTo(a.isPinned ? 1 : 0));
      }
    });
    await widget.onChanged(List<NoteFolder>.of(folders), <String>[]);
  }

  Future<void> _deleteFolder(NoteFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف پوشه؟'),
          content: Text('پوشه «${folder.name}» حذف می‌شود؛ یادداشت‌های آن باقی می‌مانند و به بخش بدون پوشه منتقل می‌شوند.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => folders.removeWhere((item) => item.id == folder.id));
    await widget.onChanged(List<NoteFolder>.of(folders), <String>[folder.id]);
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('مدیریت پوشه‌ها')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createFolder,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('پوشه جدید'),
      ),
      body: folders.isEmpty
          ? const Center(child: Text('هنوز پوشه‌ای ایجاد نشده است.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: folders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final folder = folders[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(folder.name),
                    subtitle: const Text('لمس برای نمایش یادداشت‌های پوشه'),
                    onTap: () {
                      widget.onSelectFolder(folder.id);
                      Navigator.pop(context);
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: folder.isPinned ? 'برداشتن سنجاق' : 'سنجاق کردن پوشه',
                          onPressed: () => _togglePin(folder),
                          icon: Icon(folder.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
                          color: folder.isPinned ? Theme.of(context).colorScheme.primary : null,
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'عملیات پوشه',
                          onSelected: (action) {
                            if (action == 'rename') _renameFolder(folder);
                            if (action == 'delete') _deleteFolder(folder);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'rename', child: Text('تغییر نام')),
                            PopupMenuItem(value: 'delete', child: Text('حذف پوشه')),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    ),
  );
}

class EditorPage extends StatefulWidget {
  final Note? note;
  final List<NoteTheme> themes;
  final List<String> customFonts;
  final NoteTheme initialTheme;
  final List<Note> existingNotes;
  final String? initialFolderId;
  final String? initialSearchTerm;
  final List<Note> searchNotes;
  final int initialSearchNoteIndex;
  final int initialSearchMatch;
  final Future<void> Function(Note?, int, int)? onSearchNavigate;
  const EditorPage({super.key,this.note,required this.themes,required this.customFonts,required this.initialTheme,this.existingNotes = const [], this.initialFolderId, this.initialSearchTerm, this.searchNotes = const [], this.initialSearchNoteIndex = 0, this.initialSearchMatch = 0, this.onSearchNavigate});
  @override
  State<EditorPage> createState()=>_EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final TextEditingController title;
  late final quill.QuillController controller;
  final AudioRecorder recorder = AudioRecorder();
  final AudioPlayer audioPlayer = AudioPlayer();
  final List<String> audioPaths = [];
  bool isRecording = false;
  String? currentlyPlayingEditorAudio;
  late int themeColor, themeTextColor;
  late String themeFontFamily;
  String? folderId;
  final GlobalKey<quill.EditorState> editorKey = GlobalKey<quill.EditorState>();
  List<int> searchMatchOffsets = <int>[];
  int currentSearchMatch = 0;
  static const marker = '__quill_note_v1__';
  static const toolbarSample = '>< sample text >';
  String _fontDisplayName(String family) {
    final cleaned = family
        .replaceFirst(RegExp(r'^custom_'), '')
        .replaceFirst(RegExp(r'_\d{10,}$'), '')
        .replaceAll('_', ' ')
        .trim();
    return cleaned.isEmpty ? family : cleaned;
  }
  Map<String, String> get toolbarFontFamilies => {
    for (final family in <String>{...widget.customFonts, themeFontFamily})
      family: toolbarSample + ' - ' + _fontDisplayName(family),
  };

  double _fullImageWidth() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return 360;
    final view = views.first;
    return view.physicalSize.width / view.devicePixelRatio;
  }

  List<Map<String, dynamic>> _normalizeImageWidths(List<dynamic> rawOps) {
    final width = _fullImageWidth();
    return rawOps.map((raw) {
      final op = Map<String, dynamic>.from(raw as Map);
      final insert = op['insert'];
      if (insert is Map && insert['image'] is String) {
        final attrs = Map<String, dynamic>.from(op['attributes'] as Map? ?? {});
        // Remove old fixed sizing so previously inserted images also expand.
        attrs.remove('height');
        attrs.remove('style');
        attrs['width'] = width;
        op['attributes'] = attrs;
      }
      return op;
    }).toList();
  }

  quill.Document _loadDocument(String? body, List<String> legacyImages) {
    if (body != null && body.startsWith(marker)) {
      try {
        final decoded = jsonDecode(body.substring(marker.length)) as List;
        return quill.Document.fromJson(_normalizeImageWidths(decoded));
      } catch (_) {}
    }
    final old = _decodeNoteBlocks(body ?? '');
    final ops = <Map<String, dynamic>>[];
    for (final block in old) {
      if (block['type'] == 'image' && block['path'] is String) {
        ops.add({'insert': {'image': block['path']}});
        ops.add({'insert': '\n'});
      } else {
        final text = block['text'] as String? ?? '';
        if (text.isNotEmpty) ops.add({'insert': text});
        ops.add({'insert': '\n'});
      }
    }
    if (!(body?.startsWith('__rich_note_v1__') ?? false)) {
      for (final path in legacyImages) {
        ops.add({'insert': {'image': path}});
        ops.add({'insert': '\n'});
      }
    }
    if (ops.isEmpty) ops.add({'insert': '\n'});
    return quill.Document.fromJson(_normalizeImageWidths(ops));
  }

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.note?.title ?? '');
    final doc = _loadDocument(widget.note?.body, widget.note?.images ?? const []);
    audioPlayer.onPlayerComplete.listen((_) { if (mounted) setState(() => currentlyPlayingEditorAudio = null); });
    controller = quill.QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _prepareSearchMatches();
    if (searchMatchOffsets.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _navigateSearchMatch(0);
      });
    }
    themeColor = widget.note?.themeColor ?? widget.initialTheme.backgroundColor;
    themeTextColor = widget.note?.themeTextColor ?? widget.initialTheme.textColor;
    themeFontFamily = widget.note?.themeFontFamily ?? widget.initialTheme.fontFamily;
    folderId = widget.note?.folderId ?? widget.initialFolderId;
    audioPaths.addAll(widget.note?.audios ?? const []);
    _loadEditorPreferences();
  }

  void _prepareSearchMatches() {
    final query = widget.initialSearchTerm?.trim() ?? '';
    searchMatchOffsets = <int>[];
    if (query.isEmpty) return;
    final text = controller.document.toPlainText();
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    var from = 0;
    while (from <= lowerText.length - lowerQuery.length) {
      final index = lowerText.indexOf(lowerQuery, from);
      if (index < 0) break;
      searchMatchOffsets.add(index);
      from = index + lowerQuery.length;
    }
    if (searchMatchOffsets.isNotEmpty) {
      currentSearchMatch = widget.initialSearchMatch.clamp(0, searchMatchOffsets.length - 1);
      controller.updateSelection(
        TextSelection(baseOffset: searchMatchOffsets[currentSearchMatch], extentOffset: searchMatchOffsets[currentSearchMatch] + query.length),
        quill.ChangeSource.local,
      );
    }
  }

  void _navigateSearchMatch(int direction) {
    if (searchMatchOffsets.isEmpty) return;
    final nextLocal = currentSearchMatch + direction;
    if (nextLocal < 0 || nextLocal >= searchMatchOffsets.length) {
      final targetNoteIndex = widget.searchNotes.length > 1
          ? (widget.initialSearchNoteIndex + direction + widget.searchNotes.length) % widget.searchNotes.length
          : widget.initialSearchNoteIndex + direction;
      if (targetNoteIndex >= 0 && targetNoteIndex < widget.searchNotes.length) {
        final targetText = _notePlainText(widget.searchNotes[targetNoteIndex].body).toLowerCase();
        final query = widget.initialSearchTerm?.trim().toLowerCase() ?? '';
        final targetCount = query.isEmpty ? 0 : RegExp(RegExp.escape(query)).allMatches(targetText).length;
        if (targetCount > 0) {
          widget.onSearchNavigate?.call(_createNoteResult(), targetNoteIndex, direction > 0 ? 0 : targetCount - 1);
          return;
        }
      }
      currentSearchMatch = direction > 0 ? 0 : searchMatchOffsets.length - 1;
    } else {
      currentSearchMatch = nextLocal;
    }
    final query = widget.initialSearchTerm?.trim() ?? '';
    final start = searchMatchOffsets[currentSearchMatch];
    controller.updateSelection(
      TextSelection(baseOffset: start, extentOffset: start + query.length),
      quill.ChangeSource.local,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final editorState = editorKey.currentState;
      if (editorState == null || !editorState.scrollController.hasClients) return;
      final caretRect = editorState.renderEditor.getLocalRectForCaret(TextPosition(offset: start));
      final scroll = editorState.scrollController;
      final target = (scroll.offset + caretRect.top - 80).clamp(
        scroll.position.minScrollExtent,
        scroll.position.maxScrollExtent,
      );
      scroll.animateTo(target.toDouble(), duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
    if (mounted) setState(() {});
  }

  double editorDefaultSize = 20.0;
  String editorDefaultFont = 'Estedad';

  Future<void> _loadEditorPreferences() async {
    final repository = NotebookRepository();
    editorDefaultFont = await repository.loadEditorFont();
    editorDefaultSize = await repository.loadEditorFontSize();
    if (!mounted) return;
    if (widget.note == null) {
      // A new note inherits its font from the selected note theme, not the
      // editor's last-used formatting preference.
      final themeFont = quill.Attribute.fromKeyValue('font', themeFontFamily);
      controller.formatSelection(themeFont);
      if (controller.document.length > 1) {
        controller.formatText(0, controller.document.length - 1, themeFont);
        controller.formatText(0, controller.document.length - 1,
            quill.Attribute.fromKeyValue('size', editorDefaultSize.toString()));
      }
    }
    controller.addListener(_rememberEditorFormatting);
    setState(() {});
  }

  void _rememberEditorFormatting() {
    final attributes = controller.getSelectionStyle().attributes;
    final font = attributes['font']?.value;
    final size = double.tryParse('${attributes['size']?.value ?? ''}');
    final repository = NotebookRepository();
    if (font is String && font.isNotEmpty) {
      editorDefaultFont = font;
      repository.saveEditorFont(font);
    }
    if (size != null && size >= 6 && size <= 42) {
      editorDefaultSize = size;
      repository.saveEditorFontSize(size);
    }
  }

  Future<void> addImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/notebook_images');
    if (!await folder.exists()) await folder.create(recursive: true);
    final ext = picked.path.contains('.') ? picked.path.substring(picked.path.lastIndexOf('.')) : '.jpg';
    final originalPath = '${folder.path}/${DateTime.now().microsecondsSinceEpoch}$ext';
    await File(picked.path).copy(originalPath);
    if (!mounted) return;

    // Open the drawing canvas immediately after choosing a photo. The user can
    // save an annotated copy or insert the untouched original.
    final selectedPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => DrawingPage(imagePath: originalPath)),
    );
    if (!mounted || selectedPath == null) return;
    final index = controller.selection.extentOffset.clamp(0, controller.document.length - 1);
    // Set the Quill image width attribute directly. The image embed builder
    // reads this attribute and constrains the displayed image to the editor's
    // available width; its height remains automatic to preserve aspect ratio.
    final imageWidth = MediaQuery.sizeOf(context).width;
    final imageDelta = delta.Delta()
      ..retain(index)
      ..insert(
        {'image': selectedPath},
        {'width': imageWidth},
      )
      ..insert('\n');
    controller.document.compose(imageDelta, quill.ChangeSource.local);
    controller.updateSelection(
      TextSelection.collapsed(offset: index + 2),
      quill.ChangeSource.local,
    );
  }

  Future<void> toggleRecording() async {
    if(isRecording){
      final path=await recorder.stop();
      if(path!=null&&mounted)setState(()=>audioPaths.add(path));
      if(mounted)setState(()=>isRecording=false);
      return;
    }
    if(!await recorder.hasPermission()){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('برای ضبط صدا، اجازه دسترسی به میکروفون را فعال کن.')));
      return;
    }
    final dir=await getApplicationDocumentsDirectory();
    final folder=Directory(dir.path+'/notebook_audio');
    if(!await folder.exists())await folder.create(recursive:true);
    final path=folder.path+'/voice_'+DateTime.now().microsecondsSinceEpoch.toString()+'.m4a';
    await recorder.start(const RecordConfig(encoder:AudioEncoder.aacLc),path:path);
    if(mounted)setState(()=>isRecording=true);
  }

  Future<void> playAudio(String path) async {
    try {
      if (!await File(path).exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('فایل ویس پیدا نشد.')),
          );
        }
        return;
      }
      if (currentlyPlayingEditorAudio == path && audioPlayer.state == PlayerState.playing) {
        await audioPlayer.pause();
        if (mounted) setState(() => currentlyPlayingEditorAudio = null);
        return;
      }
      await audioPlayer.stop();
      if (!mounted) return;
      setState(() => currentlyPlayingEditorAudio = path);
      await audioPlayer.play(DeviceFileSource(path), mode: PlayerMode.mediaPlayer);
    } catch (error) {
      if (mounted) {
        setState(() => currentlyPlayingEditorAudio = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('پخش ویس ناموفق بود: $error')),
        );
      }
    }
  }

  Future<void> chooseEditorTheme() async {
    final available = widget.themes.isNotEmpty
        ? widget.themes
        : <NoteTheme>[widget.initialTheme];
    final selected = await showModalBottomSheet<NoteTheme>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: Text('تم این یادداشت', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: available.map((theme) {
                      final isSelected = themeColor == theme.backgroundColor &&
                          themeTextColor == theme.textColor &&
                          themeFontFamily == theme.fontFamily;
                      return Card(
                        color: Color(theme.backgroundColor),
                        child: ListTile(
                          title: Text(theme.name, style: TextStyle(
                            color: Color(theme.textColor),
                            fontFamily: theme.fontFamily,
                            fontWeight: FontWeight.w600,
                          )),
                          subtitle: Text('نمونه متن یادداشت', style: TextStyle(
                            color: Color(theme.textColor),
                            fontFamily: theme.fontFamily,
                          )),
                          trailing: isSelected
                              ? Icon(Icons.check_circle, color: Color(theme.textColor))
                              : Icon(Icons.circle_outlined, color: Color(theme.textColor).withOpacity(.7)),
                          onTap: () => Navigator.pop(sheetContext, theme),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      themeColor = selected.backgroundColor;
      themeTextColor = selected.textColor;
      themeFontFamily = selected.fontFamily;
      // Apply the selected theme font to existing text and to the insertion
      // style, so typing immediately uses the theme font as well.
      final fontAttribute =
          quill.Attribute.fromKeyValue('font', themeFontFamily);
      if (controller.document.length > 1) {
        controller.formatText(0, controller.document.length - 1, fontAttribute);
      }
      controller.formatSelection(fontAttribute);
    });
  }


  Note? _createNoteResult() {
    final delta = controller.document.toDelta().toJson();
    final plain = controller.document.toPlainText().trim();
    final hasContent = delta.any((op) => op is Map && op['insert'] is Map);
    if (title.text.trim().isEmpty && plain.isEmpty && !hasContent) return null;
    final imagePaths = <String>[];
    for (final op in delta) {
      if (op is Map && op['insert'] is Map) {
        final image = (op['insert'] as Map)['image'];
        if (image is String && !image.startsWith('http')) imagePaths.add(image);
      }
    }
    return Note(
      widget.note?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title.text.trim(), marker + jsonEncode(delta), DateTime.now(), imagePaths,
      themeColor, themeTextColor, themeFontFamily, folderId, List.of(audioPaths),
    );
  }

  static const String _noteEntrySeparator = '-------------------------------------------------------------------';

  void save() {
    final draft = _createNoteResult();
    if (draft == null) {
      Navigator.pop(context, null);
      return;
    }

    // Existing notes are resolved by exact title across every folder.
    // Editing an already-open note continues to update that note by ID.
    if (widget.note == null) {
      final matches = widget.existingNotes
          .where((note) => note.title.trim() == draft.title.trim())
          .toList();

      if (matches.length > 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('از این عنوان چند مورد وجود دارد؛ ذخیره انجام نشد. ابتدا عنوان را یکتا کن.'),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      if (matches.length == 1) {
        final existing = matches.single;
        try {
          final previousDocument = _loadDocument(existing.body, existing.images);
          final mergedOperations = <Map<String, dynamic>>[
            ...previousDocument.toDelta().toJson().map((op) => Map<String, dynamic>.from(op as Map)),
            ...controller.document.toDelta().toJson().map((op) => Map<String, dynamic>.from(op as Map)),
            {'insert': '\n$_noteEntrySeparator\n'},
          ];
          final mergedDocument = quill.Document.fromJson(mergedOperations);
          final mergedImages = <String>{...existing.images, ...draft.images}.toList();
          final mergedAudios = <String>{...existing.audios, ...draft.audios}.toList();
          final result = Note(
            existing.id,
            existing.title,
            marker + jsonEncode(mergedDocument.toDelta().toJson()),
            DateTime.now(),
            mergedImages,
            existing.themeColor,
            existing.themeTextColor,
            existing.themeFontFamily,
            existing.folderId,
            mergedAudios,
          );
          Navigator.pop(context, result);
          return;
        } catch (error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('افزودن نوشته به یادداشت قبلی انجام نشد: $error')),
          );
          return;
        }
      }
    }

    Navigator.pop(context, draft);
  }

  Future<void> chooseExistingTitle() async {
    final searchController = TextEditingController();
    final selectedTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final query = searchController.text.trim().toLowerCase();
          final filtered = widget.existingNotes
              .where((note) => note.title.trim().isNotEmpty)
              .where((note) => note.title.toLowerCase().contains(query))
              .toList()
            ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('انتخاب عنوان قبلی'),
              content: SizedBox(
                width: double.maxFinite,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'جست‌وجوی عنوان...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('عنوانی پیدا نشد.'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, index) {
                                final note = filtered[index];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.description_outlined),
                                  title: Text(note.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                    widget.existingNotes.where((item) => item.title.trim() == note.title.trim()).length > 1
                                        ? 'عنوان تکراری؛ هنگام ذخیره پیام خطا نمایش داده می‌شود'
                                        : 'انتخاب عنوان',
                                    maxLines: 2,
                                  ),
                                  onTap: () => Navigator.pop(dialogContext, note.title),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('انصراف'),
                ),
              ],
            ),
          );
        },
      ),
    );
    searchController.dispose();
    if (selectedTitle == null || !mounted) return;
    setState(() {
      title.text = selectedTitle;
      title.selection = TextSelection.collapsed(offset: title.text.length);
    });
  }

  @override
  void dispose() {
    controller.removeListener(_rememberEditorFormatting);
    title.dispose();
    recorder.dispose();
    audioPlayer.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('یادداشت'), actions: [
        TextButton.icon(onPressed: save, icon: const Icon(Icons.check), label: const Text('ذخیره')),
      ]),
      backgroundColor: Color(themeColor),      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: title, autofocus: false,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(themeTextColor), fontFamily: themeFontFamily),
                    decoration: const InputDecoration(hintText: 'عنوان یادداشت', border: InputBorder.none),
                  ),
                ),
                IconButton(
                  tooltip: 'انتخاب از عنوان‌های قبلی',
                  onPressed: chooseExistingTitle,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (searchMatchOffsets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(tooltip: 'مورد قبلی', onPressed: () => _navigateSearchMatch(-1), icon: const Icon(Icons.keyboard_arrow_up_rounded)),
                  Text(widget.searchNotes.length > 1 ? 'یادداشت ${widget.initialSearchNoteIndex + 1} از ${widget.searchNotes.length} · مورد ${currentSearchMatch + 1} از ${searchMatchOffsets.length}' : 'مورد ${currentSearchMatch + 1} از ${searchMatchOffsets.length}'),
                  IconButton(tooltip: 'مورد بعدی', onPressed: () => _navigateSearchMatch(1), icon: const Icon(Icons.keyboard_arrow_down_rounded)),
                ],
              ),
            ),
          Expanded(
            child: quill.QuillEditor.basic(
              controller: controller,
              config: quill.QuillEditorConfig(
                editorKey: editorKey,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 0),
                maxContentWidth: MediaQuery.sizeOf(context).width,
                placeholder: 'متن یادداشتت را اینجا بنویس...',
                embedBuilders: FlutterQuillEmbeds.editorBuilders(
                  imageEmbedConfig: QuillEditorImageEmbedConfig(
                    imageProviderBuilder: (context, imageUrl) {
                      final local = File(imageUrl);
                      return local.existsSync() ? FileImage(local) : null;
                    },
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          if (audioPaths.isNotEmpty)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < audioPaths.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: InputChip(
                        avatar: Icon(
                          currentlyPlayingEditorAudio == audioPaths[i]
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_fill,
                        ),
                        label: Text('پخش ویس ${i + 1}'),
                        onPressed: () => playAudio(audioPaths[i]),
                        onDeleted: () => setState(() {
                          if (currentlyPlayingEditorAudio == audioPaths[i]) {
                            audioPlayer.stop();
                            currentlyPlayingEditorAudio = null;
                          }
                          audioPaths.removeAt(i);
                        }),
                      ),
                    ),
                ],
              ),
            ),
          quill.QuillSimpleToolbar(
            controller: controller,
            config: quill.QuillSimpleToolbarConfig(
              buttonOptions: quill.QuillSimpleToolbarButtonOptions(
                fontFamily: quill.QuillToolbarFontFamilyButtonOptions(items: toolbarFontFamilies),
                fontSize: quill.QuillToolbarFontSizeButtonOptions(items: {for (var size = 6; size <= 42; size++) '$size': '$size'}),
              ),
              multiRowsDisplay: false,
              showUndo: true,
              showRedo: true,
              showFontFamily: true,
              showFontSize: true,
              showColorButton: true,
              showBackgroundColorButton: true,
              showAlignmentButtons: true,
              showLeftAlignment: true,
              showCenterAlignment: true,
              showRightAlignment: true,
              showJustifyAlignment: false,
              showListNumbers: true,
              showBoldButton: false,
              showItalicButton: false,
              showUnderLineButton: false,
              showStrikeThrough: false,
              showSmallButton: false,
              showInlineCode: false,
              showSubscript: false,
              showSuperscript: false,
              showClearFormat: false,
              showHeaderStyle: false,
              showListBullets: false,
              showListCheck: false,
              showCodeBlock: false,
              showQuote: false,
              showIndent: false,
              showLink: false,
              showDirection: false,
              showSearchButton: false,
              customButtons: [
                quill.QuillToolbarCustomButtonOptions(
                  icon: const Icon(Icons.palette_outlined),
                  tooltip: 'انتخاب تم یادداشت',
                  onPressed: chooseEditorTheme,
                ),
                quill.QuillToolbarCustomButtonOptions(
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  tooltip: 'افزودن تصویر',
                  onPressed: addImage,
                ),
                quill.QuillToolbarCustomButtonOptions(
                  icon: Icon(
                    isRecording ? Icons.stop_circle_outlined : Icons.mic_none,
                    color: isRecording ? Colors.red : null,
                  ),
                  tooltip: isRecording ? 'پایان ضبط ویس' : 'شروع ضبط ویس',
                  onPressed: toggleRecording,
                ),
              ],
            ),
          ),
        ]),
      ),
    ),
  );
}



class Stroke{final List<Offset> points;final Color color;final double width;const Stroke(this.points,this.color,this.width);}
class DrawingPage extends StatefulWidget{
  final String imagePath;
  const DrawingPage({super.key,required this.imagePath});
  @override
  State<DrawingPage> createState()=>_DrawingPageState();
}
class _DrawingPageState extends State<DrawingPage>{
  final boundaryKey=GlobalKey();
  final strokes=<Stroke>[];
  List<Offset> active=[];
  Color color=Colors.red;
  double width=5;
  Future<void> save()async{
    try{
      final boundary=boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image=await boundary.toImage(pixelRatio:2);
      final data=await image.toByteData(format:ui.ImageByteFormat.png);
      if(data==null)return;
      final dir=await getApplicationDocumentsDirectory();
      final folder=Directory(dir.path+'/notebook_images');
      if(!await folder.exists())await folder.create(recursive:true);
      final file=File(folder.path+'/drawing_'+DateTime.now().microsecondsSinceEpoch.toString()+'.png');
      await file.writeAsBytes(data.buffer.asUint8List());
      if(mounted)Navigator.pop(context,file.path);
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('ذخیره تصویر انجام نشد. دوباره تلاش کن.')));}
  }
  @override
  Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('نقاشی روی عکس'),actions:[
      IconButton(onPressed:strokes.isEmpty?null:()=>setState(()=>strokes.removeLast()),tooltip:'بازگشت یک مرحله',icon:const Icon(Icons.undo)),
      IconButton(onPressed:()=>setState(()=>strokes.clear()),tooltip:'پاک کردن نقاشی',icon:const Icon(Icons.delete_sweep_outlined)),
      TextButton(onPressed:()=>Navigator.pop(context,widget.imagePath),child:const Text('بدون نقاشی')),
      TextButton.icon(onPressed:save,icon:const Icon(Icons.check),label:const Text('ذخیره')),
    ]),
    body:Column(children:[
      Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),child:Row(children:[
        for(final c in [Colors.red,Colors.blue,Colors.green,Colors.yellow,Colors.black,Colors.white])
          GestureDetector(onTap:()=>setState(()=>color=c),child:Container(margin:const EdgeInsets.symmetric(horizontal:5),width:27,height:27,decoration:BoxDecoration(color:c,shape:BoxShape.circle,border:Border.all(color:color==c?Colors.deepPurple:Colors.grey,width:color==c?3:1)))),
        const Spacer(),const Text('ضخامت'),SizedBox(width:100,child:Slider(value:width,min:2,max:16,onChanged:(v)=>setState(()=>width=v))),
      ])),
      Expanded(child:Center(child:RepaintBoundary(key:boundaryKey,child:GestureDetector(
        onPanStart:(d)=>setState(()=>active=[d.localPosition]),
        onPanUpdate:(d)=>setState(()=>active.add(d.localPosition)),
        onPanEnd:(_) => setState(() { if(active.isNotEmpty) strokes.add(Stroke(List.of(active),color,width)); active=[]; }),
        child:Stack(fit:StackFit.expand,children:[
          Image.file(File(widget.imagePath),fit:BoxFit.contain),
          CustomPaint(painter:DrawingPainter(strokes,active,color,width),size:Size.infinite),
        ]),
      )))),
      const Padding(padding:EdgeInsets.all(10),child:Text('با انگشت روی عکس نقاشی کن و ذخیره را بزن.')),
    ]),
  ));
}
class DrawingPainter extends CustomPainter{
  final List<Stroke> strokes;final List<Offset> active;final Color color;final double width;
  DrawingPainter(this.strokes,this.active,this.color,this.width);
  void draw(Canvas canvas,List<Offset> points,Color c,double w){
    if(points.isEmpty)return;
    final p=Paint()..color=c..strokeWidth=w..strokeCap=StrokeCap.round..strokeJoin=StrokeJoin.round..style=PaintingStyle.stroke;
    if(points.length==1){canvas.drawCircle(points.first,w/2,Paint()..color=c);return;}
    final path=Path()..moveTo(points.first.dx,points.first.dy);
    for(final point in points.skip(1)){path.lineTo(point.dx,point.dy);}
    canvas.drawPath(path,p);
  }
  @override
  void paint(Canvas canvas,Size size){for(final s in strokes){draw(canvas,s.points,s.color,s.width);}draw(canvas,active,color,width);}
  @override
  bool shouldRepaint(covariant DrawingPainter old)=>true;
}