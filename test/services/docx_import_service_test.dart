import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';

import 'package:daftarche_treid/services/docx_import_service.dart';

void main() {
  late Directory tempDirectory;
  late DocxImportService importer;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('docx_import_test_');
    importer = DocxImportService(documentsDirectory: tempDirectory);
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('keeps first paragraph, hyperlink text, table cells and run formatting', () async {
    final bytes = _docxBytes('''
      <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <w:body>
          <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>اولین پاراگراف</w:t></w:r></w:p>
          <w:p><w:hyperlink r:id="rIdLink"><w:r><w:t>متن پیوند</w:t></w:r></w:hyperlink></w:p>
          <w:tbl>
            <w:tr>
              <w:tc><w:p><w:r><w:t>خانه اول</w:t></w:r></w:p></w:tc>
              <w:tc><w:p><w:r><w:t>خانه دوم</w:t></w:r></w:p></w:tc>
            </w:tr>
          </w:tbl>
          <w:sectPr/>
        </w:body>
      </w:document>
    ''');

    final note = await importer.importBytes(bytes, fileName: 'sample.docx');
    final delta = jsonDecode(note.body.substring('__quill_note_v1__'.length)) as List;
    final document = quill.Document.fromJson(delta);
    final text = document.toPlainText();

    expect(note.title, 'sample');
    expect(text, contains('اولین پاراگراف'));
    expect(text, contains('متن پیوند'));
    expect(text, contains('خانه اول'));
    expect(text, contains('خانه دوم'));
    expect(text.indexOf('خانه اول'), lessThan(text.indexOf('خانه دوم')));
    expect(
      delta.whereType<Map>().any((op) =>
          op['insert'] == 'اولین پاراگراف' &&
          (op['attributes'] as Map?)?['bold'] == true),
      isTrue,
    );
  });

  test('extracts embedded image in its document position', () async {
    final bytes = _docxBytes('''
      <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
        <w:body>
          <w:p><w:r><w:t>قبل عکس</w:t></w:r></w:p>
          <w:p><w:r><w:drawing><a:blip r:embed="rIdImage1"/></w:drawing></w:r></w:p>
          <w:p><w:r><w:t>بعد عکس</w:t></w:r></w:p>
        </w:body>
      </w:document>
    ''', includeImage: true);

    final note = await importer.importBytes(bytes, fileName: 'with_image.docx');
    final delta = jsonDecode(note.body.substring('__quill_note_v1__'.length)) as List;
    final imageOperation = delta.indexWhere((op) =>
        op is Map && op['insert'] is Map && (op['insert'] as Map).containsKey('image'));

    expect(note.images, hasLength(1));
    expect(await File(note.images.single).exists(), isTrue);
    expect(imageOperation, greaterThan(0));
    expect(delta.take(imageOperation).any((op) => op is Map && op['insert'] == 'قبل عکس\n'), isTrue);
    expect(delta.skip(imageOperation + 1).any((op) => op is Map && op['insert'] == 'بعد عکس\n'), isTrue);
  });

  test('rejects a zip package without Word document body', () async {
    final archive = Archive()
      ..addFile(ArchiveFile('not-a-docx.txt', 4, utf8.encode('test')));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

    expect(
      () => importer.importBytes(bytes, fileName: 'invalid.docx'),
      throwsA(isA<FormatException>()),
    );
  });
}

Uint8List _docxBytes(String documentXml, {bool includeImage = false}) {
  final archive = Archive();
  final xmlBytes = utf8.encode(documentXml);
  archive.addFile(ArchiveFile('word/document.xml', xmlBytes.length, xmlBytes));

  if (includeImage) {
    const relationshipsXml = '''
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rIdImage1"
          Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image"
          Target="media/image1.png"/>
      </Relationships>
    ''';
    const contentTypesXml = '''
      <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="png" ContentType="image/png"/>
      </Types>
    ''';
    final rels = utf8.encode(relationshipsXml);
    final types = utf8.encode(contentTypesXml);
    archive
      ..addFile(ArchiveFile('word/_rels/document.xml.rels', rels.length, rels))
      ..addFile(ArchiveFile('[Content_Types].xml', types.length, types))
      ..addFile(ArchiveFile('word/media/image1.png', 8, <int>[137, 80, 78, 71, 13, 10, 26, 10]));
  }

  return Uint8List.fromList(ZipEncoder().encode(archive));
}
