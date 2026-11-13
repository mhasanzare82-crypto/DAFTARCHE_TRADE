import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/note.dart';

/// Reads WordprocessingML in document order and converts it to Quill Delta.
class DocxImportService {
  DocxImportService({required Directory documentsDirectory})
      : _imageDirectory = Directory(documentsDirectory.path + '/notebook_images');

  final Directory _imageDirectory;

  Future<Note> importBytes(Uint8List bytes, {required String fileName}) async {
    if (bytes.isEmpty) throw const FormatException('فایل Word خالی است.');
    final archive = ZipDecoder().decodeBytes(bytes);
    final documentFile = archive.findFile('word/document.xml');
    if (documentFile == null) {
      throw const FormatException('ساختار DOCX معتبر نیست؛ document.xml پیدا نشد.');
    }
    final document = XmlDocument.parse(utf8.decode(documentFile.content as List<int>));
    final body = _descendant(document, 'body');
    if (body == null) throw const FormatException('بدنه سند Word پیدا نشد.');

    final relationships = _readRelationships(archive);
    final numbering = _readNumbering(archive);
    final contentTypes = _readContentTypes(archive);
    await _imageDirectory.create(recursive: true);

    final operations = <Map<String, dynamic>>[];
    final imagePaths = <String>[];
    final createdImages = <File>[];
    var imageIndex = 0;

    final firstParagraph = _firstParagraph(body);
    final firstStyle = firstParagraph == null ? '' : _paragraphStyle(firstParagraph).toLowerCase();
    final hasTitleParagraph = firstStyle == 'title' || firstStyle == 'subtitle';
    final coreTitle = _readCoreTitle(archive);
    final paragraphTitle = hasTitleParagraph ? _paragraphText(firstParagraph!).trim() : '';
    final importedTitle = coreTitle.isNotEmpty
        ? coreTitle
        : paragraphTitle.isNotEmpty
            ? paragraphTitle
            : _fileTitle(fileName);

    void addText(String value, [Map<String, dynamic>? attributes]) {
      if (value.isEmpty) return;
      final attrs = attributes == null || attributes.isEmpty
          ? null
          : Map<String, dynamic>.from(attributes);
      if (operations.isNotEmpty &&
          operations.last['insert'] is String &&
          !(operations.last['insert'] as String).endsWith('\\n') &&
          !value.startsWith('\\n') &&
          _sameAttributes(operations.last['attributes'] as Map?, attrs)) {
        operations.last['insert'] = (operations.last['insert'] as String) + value;
      } else {
        operations.add({'insert': value, if (attrs != null) 'attributes': attrs});
      }
    }

    Future<void> addImage(XmlElement reference) async {
      final rid = _attr(reference, 'embed') ?? _attr(reference, 'id');
      final rel = rid == null ? null : relationships[rid];
      if (rel == null || rel.external) return;
      final path = _resolveTarget(rel.target);
      final entry = archive.findFile(path);
      if (entry == null) return;
      final data = entry.content as List<int>;
      if (data.isEmpty) return;
      final extension = _imageExtension(path, contentTypes);
      final name = 'docx_' +
          DateTime.now().microsecondsSinceEpoch.toString() +
          '_' +
          imageIndex.toString() +
          extension;
      imageIndex++;
      final image = File(_imageDirectory.path + '/' + name);
      await image.writeAsBytes(data, flush: true);
      createdImages.add(image);
      imagePaths.add(image.path);
      operations.add({'insert': {'image': image.path}});
    }

    Map<String, dynamic> readRunAttributes(XmlElement run) {
      final props = _directChild(run, 'rPr');
      if (props == null) return {};
      final result = <String, dynamic>{};
      bool enabled(String name) {
        final element = _descendant(props, name);
        if (element == null) return false;
        final value = _attr(element, 'val');
        return value == null ||
            (value != '0' && value.toLowerCase() != 'false' && value != 'none');
      }

      if (enabled('b')) result['bold'] = true;
      if (enabled('i')) result['italic'] = true;
      if (enabled('u')) result['underline'] = true;
      if (enabled('strike') || enabled('dstrike')) result['strike'] = true;
      final color = _attr(_descendant(props, 'color'), 'val');
      if (_hexColor(color)) result['color'] = color!.toUpperCase();
      final shade = _attr(_descendant(props, 'shd'), 'fill');
      if (_hexColor(shade)) result['background'] = shade!.toUpperCase();
      final halfPoints = int.tryParse(_attr(_descendant(props, 'sz'), 'val') ?? '');
      if (halfPoints != null && halfPoints > 0) {
        result['size'] = (halfPoints / 2).toString();
      }
      final fonts = _descendant(props, 'rFonts');
      final font = _attr(fonts, 'ascii') ?? _attr(fonts, 'hAnsi') ?? _attr(fonts, 'eastAsia');
      if (font != null && font.trim().isNotEmpty) result['font'] = font;
      return result;
    }

    Future<void> visitInline(XmlNode node, Map<String, dynamic> inherited) async {
      if (node is! XmlElement) return;
      final name = node.name.local;
      if (name == 'r') {
        final attrs = <String, dynamic>{...inherited, ...readRunAttributes(node)};
        for (final child in node.children) {
          await visitInline(child, attrs);
        }
        return;
      }
      if (name == 't') {
        addText(node.innerText, inherited);
        return;
      }
      if (name == 'tab' || name == 'ptab') {
        addText('\t', inherited);
        return;
      }
      if (name == 'br' || name == 'cr') {
        addText('\n', inherited);
        return;
      }
      if (name == 'blip' || name == 'imagedata') {
        await addImage(node);
        return;
      }
      if (name == 'del' || name == 'delText' || name == 'instrText' ||
          name == 'rPr' || name == 'pPr') return;
      // Hyperlinks, smart tags, content controls and DrawingML wrappers.
      for (final child in node.children) {
        await visitInline(child, inherited);
      }
    }

    Future<void> processParagraph(XmlElement paragraph) async {
      final props = _directChild(paragraph, 'pPr');
      final lineAttrs = <String, dynamic>{};
      if (props != null) {
        final style = _attr(_descendant(props, 'pStyle'), 'val') ?? '';
        final heading = RegExp(r'Heading([1-3])', caseSensitive: false).firstMatch(style);
        if (heading != null) lineAttrs['header'] = int.parse(heading.group(1)!);
        final align = _attr(_descendant(props, 'jc'), 'val');
        if (const {'left', 'right', 'center', 'both', 'justify', 'start', 'end'}.contains(align)) {
          lineAttrs['align'] = align == 'both' ? 'justify' : align;
        }
        final numId = _attr(_descendant(props, 'numId'), 'val');
        if (numId != null && numId != '0') {
          lineAttrs['list'] = numbering[numId] == 'bullet' ? 'bullet' : 'ordered';
        }
      }
      for (final child in paragraph.children) {
        if (child is XmlElement && child.name.local == 'pPr') continue;
        await visitInline(child, const {});
      }
      addText('\n', lineAttrs);
    }

    Future<void> processBlock(XmlNode node) async {
      if (node is! XmlElement) return;
      final name = node.name.local;
      if (name == 'p') {
        if (hasTitleParagraph && identical(node, firstParagraph)) return;
        await processParagraph(node);
        return;
      }
      if (name == 'tbl') {
        final rows = node.children.whereType<XmlElement>()
            .where((element) => element.name.local == 'tr');
        for (final row in rows) {
          final cells = row.children.whereType<XmlElement>()
              .where((element) => element.name.local == 'tc').toList();
          for (var i = 0; i < cells.length; i++) {
            if (i > 0) addText('\t');
            for (final child in cells[i].children) {
              await processBlock(child);
            }
          }
          final last = operations.isEmpty ? null : operations.last['insert'];
          if (last is! String || !last.endsWith('\n')) addText('\n');
        }
        return;
      }
      // Recurse through sdtContent, customXml and other Word block wrappers.
      for (final child in node.children) {
        await processBlock(child);
      }
    }

    try {
      for (final child in body.children) {
        await processBlock(child);
      }
      if (operations.isEmpty) operations.add({'insert': '\n'});
      final lastInsert = operations.last['insert'];
      if (lastInsert is String && !lastInsert.endsWith('\n')) {
        addText('\n');
      } else if (lastInsert is Map) {
        operations.add({'insert': '\n'});
      }
      return Note(
        DateTime.now().microsecondsSinceEpoch.toString(),
        importedTitle,
        '__quill_note_v1__' + jsonEncode(operations),
        DateTime.now(),
        imagePaths,
      );
    } catch (_) {
      for (final image in createdImages) {
        try {
          if (await image.exists()) await image.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Map<String, _DocxRelationship> _readRelationships(Archive archive) {
    final result = <String, _DocxRelationship>{};
    final file = archive.findFile('word/_rels/document.xml.rels');
    if (file == null) return result;
    final xml = XmlDocument.parse(utf8.decode(file.content as List<int>));
    for (final element in xml.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'Relationship') continue;
      final id = _attr(element, 'Id');
      final target = _attr(element, 'Target');
      if (id != null && target != null) {
        result[id] = _DocxRelationship(
          target,
          _attr(element, 'TargetMode')?.toLowerCase() == 'external',
        );
      }
    }
    return result;
  }

  Map<String, String> _readNumbering(Archive archive) {
    final result = <String, String>{};
    final file = archive.findFile('word/numbering.xml');
    if (file == null) return result;
    final xml = XmlDocument.parse(utf8.decode(file.content as List<int>));
    final formats = <String, String>{};
    for (final element in xml.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'abstractNum') continue;
      final id = _attr(element, 'abstractNumId');
      final format = _attr(_descendant(element, 'numFmt'), 'val');
      if (id != null && format != null) formats[id] = format;
    }
    for (final element in xml.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'num') continue;
      final id = _attr(element, 'numId');
      final abstractId = _attr(_descendant(element, 'abstractNumId'), 'val');
      if (id != null && abstractId != null && formats.containsKey(abstractId)) {
        result[id] = formats[abstractId]!;
      }
    }
    return result;
  }

  Map<String, String> _readContentTypes(Archive archive) {
    final result = <String, String>{};
    final file = archive.findFile('[Content_Types].xml');
    if (file == null) return result;
    final xml = XmlDocument.parse(utf8.decode(file.content as List<int>));
    for (final element in xml.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'Default') continue;
      final extension = _attr(element, 'Extension');
      final type = _attr(element, 'ContentType');
      if (extension != null && type != null) result[extension.toLowerCase()] = type;
    }
    return result;
  }

  String _readCoreTitle(Archive archive) {
    final file = archive.findFile('docProps/core.xml');
    if (file == null) return '';
    try {
      return _descendant(
        XmlDocument.parse(utf8.decode(file.content as List<int>)),
        'title',
      )?.innerText.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  XmlElement? _firstParagraph(XmlElement body) {
    for (final element in body.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'p') return element;
    }
    return null;
  }

  String _paragraphStyle(XmlElement paragraph) {
    return _attr(_descendant(_directChild(paragraph, 'pPr'), 'pStyle'), 'val') ?? '';
  }

  String _paragraphText(XmlElement paragraph) => paragraph.descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == 't')
      .map((element) => element.innerText)
      .join();

  String _fileTitle(String fileName) {
    final base = fileName.replaceAll('\\', '/').split('/').last;
    final dot = base.lastIndexOf('.');
    final title = dot > 0 ? base.substring(0, dot) : base;
    return title.trim().isEmpty ? 'یادداشت واردشده' : title.trim();
  }

  String _resolveTarget(String target) {
    final clean = Uri.decodeComponent(target.split('?').first.split('#').first);
    final parts = <String>[];
    final segments = clean.startsWith('/')
        ? clean.substring(1).split('/')
        : <String>['word', ...clean.split('/')];
    for (final segment in segments) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(segment);
      }
    }
    return parts.join('/');
  }

  String _imageExtension(String path, Map<String, String> types) {
    final base = path.split('/').last;
    final dot = base.lastIndexOf('.');
    final ext = dot < 0 ? '' : base.substring(dot + 1).toLowerCase();
    const mimeExtensions = {
      'image/png': '.png',
      'image/jpeg': '.jpg',
      'image/gif': '.gif',
      'image/webp': '.webp',
      'image/bmp': '.bmp',
      'image/tiff': '.tif',
      'image/svg+xml': '.svg',
    };
    return mimeExtensions[types[ext]] ?? (ext.isEmpty ? '.png' : '.' + ext);
  }

  static String? _attr(XmlElement? element, String name) {
    if (element == null) return null;
    for (final attribute in element.attributes) {
      if (attribute.name.local == name) return attribute.value;
    }
    return null;
  }

  static XmlElement? _directChild(XmlElement element, String name) {
    for (final child in element.children.whereType<XmlElement>()) {
      if (child.name.local == name) return child;
    }
    return null;
  }

  static XmlElement? _descendant(XmlNode? node, String name) {
    if (node == null) return null;
    for (final child in node.descendants.whereType<XmlElement>()) {
      if (child.name.local == name) return child;
    }
    return null;
  }

  static bool _hexColor(String? value) =>
      value != null && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value);

  static bool _sameAttributes(Map? left, Map<String, dynamic>? right) {
    if (left == null || left.isEmpty) return right == null || right.isEmpty;
    if (right == null || left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }
}

class _DocxRelationship {
  const _DocxRelationship(this.target, this.external);
  final String target;
  final bool external;
}
