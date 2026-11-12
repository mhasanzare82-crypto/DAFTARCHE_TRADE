import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const NotebookApp());
class NotebookApp extends StatelessWidget {
  const NotebookApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false, title: 'دفترچه یادداشت',
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6956A5)), scaffoldBackgroundColor: const Color(0xFFF7F5FB)),
    localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate, GlobalWidgetsLocalizations.delegate, quill.FlutterQuillLocalizations.delegate],
    supportedLocales: const [Locale('fa'), Locale('en')],
    home: const NotesPage(),
  );
}

class Note {
  final String id, title, body;
  final DateTime updated;
  final List<String> images;
  final int themeColor, themeTextColor;
  final String themeFontFamily;
  final String? folderId;
  const Note(this.id, this.title, this.body, this.updated, [this.images = const [], this.themeColor = 0xFFEDE7F6, this.themeTextColor = 0xFF24212A, this.themeFontFamily = 'sans-serif', this.folderId]);
  Map<String, dynamic> toJson() => {'id':id,'title':title,'body':body,'updated':updated.toIso8601String(),'images':images,'themeColor':themeColor,'themeTextColor':themeTextColor,'themeFontFamily':themeFontFamily,'folderId':folderId};
  factory Note.fromJson(Map<String,dynamic> j) => Note(j['id'],j['title'],j['body'],DateTime.parse(j['updated']),List<String>.from(j['images'] ?? const []),j['themeColor'] ?? 0xFFEDE7F6,j['themeTextColor'] ?? 0xFF24212A,j['themeFontFamily'] ?? 'sans-serif',j['folderId'] as String?);
}

class NoteFolder {
  final String id,name;
  const NoteFolder(this.id,this.name);
  Map<String,dynamic> toJson()=>{'id':id,'name':name};
  factory NoteFolder.fromJson(Map<String,dynamic> j)=>NoteFolder(j['id'] as String,j['name'] as String);
}

class NoteTheme {
  final String name;
  final int backgroundColor, textColor;
  final String fontFamily;
  const NoteTheme(this.name,this.backgroundColor,[this.textColor=0xFF24212A,this.fontFamily='sans-serif']);
  Map<String,dynamic> toJson()=>{'name':name,'backgroundColor':backgroundColor,'textColor':textColor,'fontFamily':fontFamily};
  factory NoteTheme.fromJson(Map<String,dynamic> j)=>NoteTheme(j['name'] as String,j['backgroundColor'] ?? j['color'] as int,j['textColor'] ?? 0xFF24212A,j['fontFamily'] ?? 'sans-serif');
}

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});
  @override
  State<NotesPage> createState() => _NotesPageState();
}
class _NotesPageState extends State<NotesPage> {
  final notes=<Note>[];
  final themes=<NoteTheme>[];
  final folders=<NoteFolder>[];
  final search=TextEditingController();
  String? selectedFolderId;
  bool loading=true;
  static const defaultThemes=[NoteTheme('یاسی',0xFFEDE7F6),NoteTheme('آبی',0xFFE3F2FD),NoteTheme('سبز',0xFFE8F5E9),NoteTheme('صورتی',0xFFFCE4EC),NoteTheme('هلویی',0xFFFFEAD5)];

  @override
  void initState(){super.initState();search.addListener(()=>setState((){}));load();}
  Future<void> load() async {
    final p=await SharedPreferences.getInstance();
    try { notes.addAll((jsonDecode(p.getString('notebook_notes')??'[]') as List).map((e)=>Note.fromJson(e))); } catch(_){}
    try { themes.addAll((jsonDecode(p.getString('notebook_themes')??'[]') as List).map((e)=>NoteTheme.fromJson(e))); } catch(_){}
    try { folders.addAll((jsonDecode(p.getString('notebook_folders')??'[]') as List).map((e)=>NoteFolder.fromJson(e))); } catch(_){}
    if(themes.isEmpty) themes.addAll(defaultThemes);
    if(mounted)setState(()=>loading=false);
    await persistThemes();
  }
  Future<void> persist() async {
    final p=await SharedPreferences.getInstance();
    await p.setString('notebook_notes',jsonEncode(notes.map((n)=>n.toJson()).toList()));
  }
  Future<void> persistFolders() async {
    final p=await SharedPreferences.getInstance();
    await p.setString('notebook_folders',jsonEncode(folders.map((f)=>f.toJson()).toList()));
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
    setState((){final i=notes.indexWhere((n)=>n.id==note.id);if(i>=0){final n=notes[i];notes[i]=Note(n.id,n.title,n.body,n.updated,List.of(n.images),n.themeColor,n.themeTextColor,n.themeFontFamily,id);}});
    await persist();
  }
  Future<void> persistThemes() async {
    final p=await SharedPreferences.getInstance();
    await p.setString('notebook_themes',jsonEncode(themes.map((t)=>t.toJson()).toList()));
  }
  Future<void> manageThemes() async {
    final result=await showDialog<List<NoteTheme>>(context:context,builder:(context)=>ThemeManagerDialog(initialThemes:List.of(themes)));
    if(result!=null){
      setState((){themes..clear()..addAll(result);});
      await persistThemes();
    }
  }
  List<Note> get filtered {
    final q=search.text.trim().toLowerCase();
    final list=notes.where((n)=>(selectedFolderId==null||n.folderId==selectedFolderId)&&(n.title.toLowerCase().contains(q)||_notePlainText(n.body).toLowerCase().contains(q))).toList();
    list.sort((a,b)=>b.updated.compareTo(a.updated));return list;
  }
  Future<void> edit([Note? note]) async {
    final selected=note==null?(themes.isEmpty?defaultThemes.first:themes[Random().nextInt(themes.length)]):NoteTheme('فعلی',note.themeColor,note.themeTextColor,note.themeFontFamily);
    final result=await Navigator.push<Note>(context,MaterialPageRoute(builder:(_)=>EditorPage(note:note,themes:themes,initialTheme:selected,initialFolderId:note?.folderId??selectedFolderId)));
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
    final contentTypes = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="jpg" ContentType="image/jpeg"/><Default Extension="png" ContentType="image/png"/><Default Extension="gif" ContentType="image/gif"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>';
    final rootRels = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>';
    final docRels = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${relationships.join()}</Relationships>';
    archive
      ..addFile(ArchiveFile('[Content_Types].xml', contentTypes.length, utf8.encode(contentTypes)))
      ..addFile(ArchiveFile('_rels/.rels', rootRels.length, utf8.encode(rootRels)))
      ..addFile(ArchiveFile('word/_rels/document.xml.rels', docRels.length, utf8.encode(docRels)))
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
    final zip = ZipDecoder().decodeBytes(bytes);
    final documentFile = zip.findFile('word/document.xml');
    if (documentFile == null) return null;
    final xml = XmlDocument.parse(utf8.decode(documentFile.content as List<int>));
    final relsFile = zip.findFile('word/_rels/document.xml.rels');
    final relationships = <String, String>{};
    if (relsFile != null) {
      final rels = XmlDocument.parse(utf8.decode(relsFile.content as List<int>));
      for (final rel in rels.descendants.whereType<XmlElement>().where((e) => e.name.local == 'Relationship')) {
        final id = rel.attributes.where((a) => a.name.local == 'Id').map((a) => a.value).firstOrNull;
        final target = rel.attributes.where((a) => a.name.local == 'Target').map((a) => a.value).firstOrNull;
        if (id != null && target != null) relationships[id] = target;
      }
    }
    final imageDirRoot = await getApplicationDocumentsDirectory();
    final imageDir = Directory('${imageDirRoot.path}/notebook_images');
    if (!await imageDir.exists()) await imageDir.create(recursive: true);
    final operations = <Map<String, dynamic>>[];
    final imagePaths = <String>[];
    final paragraphs = xml.descendants.whereType<XmlElement>().where((e) => e.name.local == 'p').toList();
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
        if (pPr.descendants.whereType<XmlElement>().any((e) => e.name.local == 'numPr')) lineAttrs['list'] = 'bullet';
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
          final mediaPath = target.startsWith('/') ? target.substring(1) : target.startsWith('../') ? 'word/${target.substring(3)}' : 'word/$target';
          final normalized = mediaPath;
          final mediaFile = zip.findFile(normalized) ?? zip.findFile(mediaPath);
          if (mediaFile == null) continue;
          final ext = normalized.contains('.') ? normalized.substring(normalized.lastIndexOf('.')) : '.png';
          final path = '${imageDir.path}/imported_${DateTime.now().microsecondsSinceEpoch}_${imagePaths.length}$ext';
          await File(path).writeAsBytes(mediaFile.content as List<int>);
          imagePaths.add(path);
          operations.add({'insert': {'image': path}});
        }
      }
      operations.add({'insert': '\n', if (lineAttrs.isNotEmpty) 'attributes': lineAttrs});
    }
    if (operations.isEmpty) return null;
    final plain = operations.where((op) => op['insert'] is String).map((op) => op['insert'] as String).join().trim();
    final title = plain.split('\n').firstOrNull?.trim() ?? '';
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    return Note(id, title, '__quill_note_v1__${jsonEncode(operations.skipWhile((op) => op['insert'] is String && (op['insert'] as String).trim().isEmpty).toList())}', DateTime.now(), imagePaths);
  }

  Future<void> importDocx() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.custom,
          allowedExtensions: ['docx']);
      if (files.isEmpty) return;
      final imported = <Note>[];
      for (final file in files) {
        try { final note = await _noteFromDocx(file); if (note != null) imported.add(note); } catch (_) {}
      }
      if (imported.isNotEmpty) { setState(() => notes.addAll(imported)); await persist(); }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${imported.length} فایل Word وارد شد')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ورود فایل‌ها انجام نشد: $e')));
    }
  }

  Future<void> createBackup() async {
    try {
      final imageData = <String, String>{};
      for (final note in notes) {
        final paths = <String>{...note.images, ..._decodeNoteBlocks(note.body)
            .where((b) => b['type'] == 'image').map((b) => b['path'] as String)};
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
        final blocks = _decodeNoteBlocks(n.body).map((block) {
          if (block['type'] == 'image' && restoredPaths.containsKey(block['path'])) {
            return {...block, 'path': restoredPaths[block['path']]};
          }
          return block;
        }).toList();
        final body = n.body.startsWith('__rich_note_v1__') ? '__rich_note_v1__${jsonEncode(blocks)}' : n.body;
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

  void showNoteMenu(Note note) {
    showModalBottomSheet<void>(context: context, builder: (sheetContext) =>
      Directionality(textDirection: TextDirection.rtl, child: SafeArea(child: Wrap(children: [
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
  void dispose(){search.dispose();super.dispose();}
  @override
  Widget build(BuildContext context){
    final items=filtered;
    return Directionality(textDirection:TextDirection.rtl,child:Scaffold(
      appBar:AppBar(title:const Text('دفترچه یادداشت',style:TextStyle(fontWeight:FontWeight.bold)),actions:[PopupMenuButton<String>(tooltip:'ورود و خروجی فایل‌ها',onSelected:(value){if(value=='import')importDocx();if(value=='export')exportDocx(notes);if(value=='backup')createBackup();if(value=='restore')restoreBackup();},itemBuilder:(context)=>const [PopupMenuItem(value:'import',child:ListTile(leading:Icon(Icons.file_open),title:Text('ورود گروهی DOCX'))),PopupMenuItem(value:'export',child:ListTile(leading:Icon(Icons.file_download),title:Text('خروجی گروهی DOCX'))),PopupMenuDivider(),PopupMenuItem(value:'backup',child:ListTile(leading:Icon(Icons.backup_outlined),title:Text('ساخت فایل پشتیبان'))),PopupMenuItem(value:'restore',child:ListTile(leading:Icon(Icons.settings_backup_restore),title:Text('بازیابی فایل پشتیبان')))]),IconButton(tooltip:'ایجاد پوشه',onPressed:createFolder,icon:const Icon(Icons.create_new_folder_outlined)),IconButton(tooltip:'مدیریت تم‌ها',onPressed:manageThemes,icon:const Icon(Icons.palette_outlined)),IconButton(onPressed:()=>edit(),icon:const Icon(Icons.add_rounded))]),
      floatingActionButton:FloatingActionButton.extended(onPressed:()=>edit(),icon:const Icon(Icons.edit_note_rounded),label:const Text('یادداشت جدید')),
      body:SafeArea(child:Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(20,8,20,18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          TextField(controller:search,decoration:InputDecoration(hintText:'جستجو در یادداشت‌ها...',prefixIcon:const Icon(Icons.search),suffixIcon:search.text.isEmpty?null:IconButton(onPressed:search.clear,icon:const Icon(Icons.close)),filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:BorderSide.none))),
          const SizedBox(height:14),
          Text('ایده‌هایت را اینجا ثبت کن ✨',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),
          const SizedBox(height:6),Text(notes.length.toString()+' یادداشت در دفترچه‌ات داری',style:TextStyle(color:Colors.grey.shade600)),
          const SizedBox(height:12),
          const Text('پوشه‌ها',style:TextStyle(fontWeight:FontWeight.bold)),
          SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
            Padding(padding:const EdgeInsets.only(left:8),child:ChoiceChip(label:const Text('همه'),selected:selectedFolderId==null,onSelected:(_)=>setState(()=>selectedFolderId=null))),
            ...folders.map((folder)=>Padding(padding:const EdgeInsets.only(left:8),child:ChoiceChip(avatar:const Icon(Icons.folder_outlined,size:17),label:Text(folder.name),selected:selectedFolderId==folder.id,onSelected:(_)=>setState(()=>selectedFolderId=folder.id)))),
          ])),
          const SizedBox(height:16),

        ])),
        Expanded(child:loading?const Center(child:CircularProgressIndicator()):items.isEmpty
          ?Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[const Icon(Icons.menu_book_rounded,size:64,color:Color(0xFF9B8CCB)),const SizedBox(height:12),Text(search.text.isEmpty?(selectedFolderId==null?'دفترچه‌ات هنوز خالی است':'این پوشه هنوز خالی است'):'یادداشتی پیدا نشد',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:8),Text(search.text.isEmpty?'اولین یادداشتت را بنویس.':'عبارت دیگری را جستجو کن.'),if(search.text.isEmpty)...[const SizedBox(height:14),FilledButton(onPressed:()=>edit(),child:const Text('نوشتن اولین یادداشت'))]]))
          :ListView.separated(padding:const EdgeInsets.fromLTRB(20,0,20,100),itemCount:items.length,separatorBuilder:(_,__)=>const SizedBox(height:10),itemBuilder:(_,i){
            final n=items[i];
            return Card(elevation:0,color:Color(n.themeColor),child:InkWell(onTap:()=>edit(n),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[Expanded(child:Text(n.title.isEmpty?'بدون عنوان':n.title,style:TextStyle(fontWeight:FontWeight.bold,fontSize:16,color:Color(n.themeTextColor),fontFamily:n.themeFontFamily))),IconButton(tooltip:'گزینه‌های یادداشت',onPressed:()=>showNoteMenu(n),icon:const Icon(Icons.more_vert))]),
              if(_notePlainText(n.body).isNotEmpty)Text(_notePlainText(n.body),maxLines:3,overflow:TextOverflow.ellipsis,style:TextStyle(color:Color(n.themeTextColor),fontFamily:n.themeFontFamily)),
              if(n.images.isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Text(n.images.length.toString()+' تصویر پیوست شده',style:TextStyle(color:Color(n.themeTextColor).withOpacity(.7),fontSize:12,fontFamily:n.themeFontFamily))),
              const SizedBox(height:8),Text(date(n.updated),style:TextStyle(fontSize:11,color:Color(n.themeTextColor).withOpacity(.65),fontFamily:n.themeFontFamily)),
            ]))));
          })),
      ])),
    ));
  }
}

class EditorPage extends StatefulWidget {
  final Note? note;
  final List<NoteTheme> themes;
  final NoteTheme initialTheme;
  final String? initialFolderId;
  const EditorPage({super.key,this.note,required this.themes,required this.initialTheme, this.initialFolderId});
  @override
  State<EditorPage> createState()=>_EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final TextEditingController title;
  late final quill.QuillController controller;
  late int themeColor, themeTextColor;
  late String themeFontFamily;
  String? folderId;
  static const marker = '__quill_note_v1__';

  quill.Document _loadDocument(String? body, List<String> legacyImages) {
    if (body != null && body.startsWith(marker)) {
      try { return quill.Document.fromJson(jsonDecode(body.substring(marker.length)) as List); } catch (_) {}
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
    return quill.Document.fromJson(ops);
  }

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.note?.title ?? '');
    final doc = _loadDocument(widget.note?.body, widget.note?.images ?? const []);
    controller = quill.QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
    themeColor = widget.note?.themeColor ?? widget.initialTheme.backgroundColor;
    themeTextColor = widget.note?.themeTextColor ?? widget.initialTheme.textColor;
    themeFontFamily = widget.note?.themeFontFamily ?? widget.initialTheme.fontFamily;
    folderId = widget.note?.folderId ?? widget.initialFolderId;
  }

  Future<void> addImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/notebook_images');
    if (!await folder.exists()) await folder.create(recursive: true);
    final ext = picked.path.contains('.') ? picked.path.substring(picked.path.lastIndexOf('.')) : '.jpg';
    final path = '${folder.path}/${DateTime.now().microsecondsSinceEpoch}$ext';
    await File(picked.path).copy(path);
    if (!mounted) return;
    final index = controller.selection.extentOffset.clamp(0, controller.document.length - 1);
    controller.document.insert(index, quill.BlockEmbed.image(path));
    controller.document.insert(index + 1, '\n');
    controller.updateSelection(TextSelection.collapsed(offset: index + 2), quill.ChangeSource.local);
  }

  void save() {
    final delta = controller.document.toDelta().toJson();
    final plain = controller.document.toPlainText().trim();
    final hasContent = delta.any((op) => op is Map && op['insert'] is Map);
    if (title.text.trim().isEmpty && plain.isEmpty && !hasContent) { Navigator.pop(context); return; }
    final imagePaths = <String>[];
    for (final op in delta) {
      if (op is Map && op['insert'] is Map) {
        final image = (op['insert'] as Map)['image'];
        if (image is String && !image.startsWith('http')) imagePaths.add(image);
      }
    }
    Navigator.pop(context, Note(
      widget.note?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title.text.trim(), marker + jsonEncode(delta), DateTime.now(), imagePaths,
      themeColor, themeTextColor, themeFontFamily, folderId,
    ));
  }

  @override
  void dispose() {
    title.dispose();
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
      backgroundColor: Color(themeColor),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
            controller: title, autofocus: true,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(themeTextColor), fontFamily: themeFontFamily),
            decoration: const InputDecoration(hintText: 'عنوان یادداشت', border: InputBorder.none),
          ),
          const SizedBox(height: 8),
          quill.QuillSimpleToolbar(
            controller: controller,
            config: quill.QuillSimpleToolbarConfig(
              multiRowsDisplay: false,
              embedButtons: FlutterQuillEmbeds.toolbarButtons(),
              showFontFamily: true,
              showFontSize: true,
              showBoldButton: true,
              showItalicButton: true,
              showUnderLineButton: true,
              showStrikeThrough: true,
              showColorButton: true,
              showBackgroundColorButton: true,
              showHeaderStyle: true,
              showListNumbers: true,
              showListBullets: true,
              showAlignmentButtons: true,
              showQuote: true,
              showCodeBlock: true,
              showClearFormat: true,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: quill.QuillEditor.basic(
              controller: controller,
              config: quill.QuillEditorConfig(
                padding: const EdgeInsets.symmetric(vertical: 14),
                placeholder: 'متن یادداشتت را اینجا بنویس...',
                embedBuilders: FlutterQuillEmbeds.editorBuilders(
                  imageEmbedConfig: quill.QuillEditorImageEmbedConfig(
                    imageProviderBuilder: (context, imageUrl) {
                      final local = File(imageUrl);
                      return local.existsSync() ? FileImage(local) : null;
                    },
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: addImage,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('افزودن عکس از گالری'),
          )),
        ]),
      ),
    ),
  );
}

class ThemeManagerDialog extends StatefulWidget {
  final List<NoteTheme> initialThemes;
  const ThemeManagerDialog({super.key, required this.initialThemes});
  @override
  State<ThemeManagerDialog> createState() => _ThemeManagerDialogState();
}
class _ThemeManagerDialogState extends State<ThemeManagerDialog> {
  late List<NoteTheme> items;
  @override
  void initState() { super.initState(); items = List.of(widget.initialThemes); }
  Future<void> editTheme([NoteTheme? old]) async {
    final result = await showDialog<NoteTheme>(context: context, builder: (_) => ThemeEditorDialog(theme: old));
    if (result == null) return;
    setState(() {
      if (old == null) { items.add(result); }
      else { final index = items.indexOf(old); if (index >= 0) items[index] = result; }
    });
  }
  Future<void> deleteTheme(NoteTheme theme) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف تم؟'),
        content: Text('تم «${theme.name}» حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed == true) setState(() => items.remove(theme));
  }
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('مدیریت تم‌ها'),
        content: SizedBox(
          width: 420,
          child: items.isEmpty
              ? const Text('هنوز تمی نساخته‌ای.')
              : ListView(
                  shrinkWrap: true,
                  children: items.map((theme) => Card(
                    color: Color(theme.backgroundColor),
                    child: ListTile(
                      title: Text(theme.name, style: TextStyle(color: Color(theme.textColor), fontFamily: theme.fontFamily)),
                      subtitle: Text('پس‌زمینه، رنگ متن و فونت', style: TextStyle(color: Color(theme.textColor).withOpacity(.75))),
                      leading: CircleAvatar(backgroundColor: Color(theme.backgroundColor), child: Icon(Icons.text_fields, color: Color(theme.textColor))),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(tooltip: 'ویرایش', onPressed: () => editTheme(theme), icon: const Icon(Icons.edit_outlined)),
                        IconButton(tooltip: 'حذف', onPressed: () => deleteTheme(theme), icon: const Icon(Icons.delete_outline)),
                      ]),
                      onTap: () => editTheme(theme),
                    ),
                  )).toList(),
                ),
        ),
        actions: [
          TextButton.icon(onPressed: () => editTheme(), icon: const Icon(Icons.add), label: const Text('ساخت تم')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, items), child: const Text('ذخیره')),
        ],
      ),
    );
  }
}

class ThemeEditorDialog extends StatefulWidget{
  final NoteTheme? theme;
  const ThemeEditorDialog({super.key,this.theme});
  @override
  State<ThemeEditorDialog> createState()=>_ThemeEditorDialogState();
}
class _ThemeEditorDialogState extends State<ThemeEditorDialog>{
  late final TextEditingController name,font;
  late int background,textColor;
  static const backgrounds=[
    0xFFFFEBEE,0xFFFCE4EC,0xFFF3E5F5,0xFFEDE7F6,0xFFE8EAF6,
    0xFFE3F2FD,0xFFE1F5FE,0xFFE0F7FA,0xFFE0F2F1,0xFFE8F5E9,
    0xFFF1F8E9,0xFFF9FBE7,0xFFFFFDE7,0xFFFFF8E1,0xFFFFF3E0,
    0xFFFFEAD5,0xFFFBE9E7,0xFFEFEBE9,0xFFECEFF1,0xFFE0E0E0,
    0xFFCFD8DC,0xFFB3E5FC,0xFFB2DFDB,0xFFC8E6C9,0xFFDCEDC8,
    0xFFFFF9C4,0xFFFFE0B2,0xFFFFCCBC,0xFFD7CCC8,0xFFD1C4E9,
  ];
  static const textColors=[
    0xFF16131C,0xFF000000,0xFF263238,0xFF37474F,0xFF1A237E,
    0xFF0D47A1,0xFF006064,0xFF004D40,0xFF1B5E20,0xFF33691E,
    0xFF827717,0xFF5D4037,0xFF4E342E,0xFF6D4C41,0xFF880E4F,
    0xFFAD1457,0xFF6A1B9A,0xFF4527A0,0xFFB71C1C,0xFFFFFFFF,
  ];
  static const commonFonts=['sans-serif','serif','monospace','sans-serif-condensed','sans-serif-light','sans-serif-medium','cursive'];
  @override
  void initState(){
    super.initState();
    final t=widget.theme;
    name=TextEditingController(text:t?.name??'');
    font=TextEditingController(text:t?.fontFamily??'sans-serif');
    background=t?.backgroundColor??backgrounds[3];
    textColor=t?.textColor??textColors.first;
  }
  @override
  void dispose(){name.dispose();font.dispose();super.dispose();}
  @override
  Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:AlertDialog(
    title:Text(widget.theme==null?'ساخت تم جدید':'ویرایش تم'),
    content:SingleChildScrollView(child:SizedBox(width:420,child:Column(
      mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        TextField(controller:name,maxLength:24,decoration:const InputDecoration(labelText:'نام دلخواه تم',hintText:'مثلاً شب آرام')),
        const SizedBox(height:12),const Text('۱. رنگ پس‌زمینه (۳۰ رنگ)'),
        const SizedBox(height:8),
        Wrap(spacing:9,runSpacing:9,children:backgrounds.map((c)=>GestureDetector(
          onTap:()=>setState(()=>background=c),
          child:Container(width:32,height:32,decoration:BoxDecoration(color:Color(c),shape:BoxShape.circle,border:Border.all(color:background==c?Colors.deepPurple:Colors.black26,width:background==c?3:1))),
        )).toList()),
        const SizedBox(height:16),const Text('۲. رنگ متن'),
        const SizedBox(height:8),
        Wrap(spacing:9,runSpacing:9,children:textColors.map((c)=>GestureDetector(
          onTap:()=>setState(()=>textColor=c),
          child:Container(width:30,height:30,decoration:BoxDecoration(color:Color(c),shape:BoxShape.circle,border:Border.all(color:textColor==c?Colors.deepPurple:Colors.black26,width:textColor==c?3:1))),
        )).toList()),
        const SizedBox(height:16),const Text('۳. فونت دلخواه'),
        TextField(controller:font,onChanged:(_)=>setState((){}),decoration:const InputDecoration(labelText:'نام فونت دستگاه یا فونت برنامه',hintText:'مثلاً sans-serif')),
        const Text('برای نمایش دقیق، فونت باید روی دستگاه موجود یا به برنامه اضافه شده باشد.',style:TextStyle(fontSize:11,color:Colors.black54)),
        const SizedBox(height:6),
        Wrap(spacing:6,children:commonFonts.map((f)=>ActionChip(label:Text(f,style:TextStyle(fontFamily:f,fontSize:11)),onPressed:()=>setState(()=>font.text=f))).toList()),
        const SizedBox(height:16),const Text('پیش‌نمایش'),
        Container(width:double.infinity,padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:Color(background),borderRadius:BorderRadius.circular(12)),child:Text('یادداشت نمونه؛ این متن با فونت و رنگ انتخابی نمایش داده می‌شود.',style:TextStyle(color:Color(textColor),fontFamily:font.text.trim().isEmpty?'sans-serif':font.text.trim(),fontSize:16))),
      ],
    ))),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(context),child:const Text('انصراف')),
      FilledButton(onPressed:()=>Navigator.pop(context,NoteTheme(name.text.trim().isEmpty?'تم بدون نام':name.text.trim(),background,textColor,font.text.trim().isEmpty?'sans-serif':font.text.trim())),child:const Text('ذخیره تم')),
    ],
  ));
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
      IconButton(onPressed:strokes.isEmpty?null:()=>setState(()=>strokes.removeLast()),icon:const Icon(Icons.undo)),
      IconButton(onPressed:()=>setState(()=>strokes.clear()),icon:const Icon(Icons.delete_sweep_outlined)),
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
