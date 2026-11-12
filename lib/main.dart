import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const NotebookApp());

class NotebookApp extends StatelessWidget {
  const NotebookApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'دفترچه یادداشت',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6956A5)),
      scaffoldBackgroundColor: const Color(0xFFF7F5FB),
    ),
    home: const NotesPage(),
  );
}

class Note {
  final String id, title, body;
  final DateTime updated;
  const Note(this.id, this.title, this.body, this.updated);
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'body': body, 'updated': updated.toIso8601String()};
  factory Note.fromJson(Map<String, dynamic> j) => Note(j['id'], j['title'], j['body'], DateTime.parse(j['updated']));
}

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});
  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final notes = <Note>[];
  final search = TextEditingController();
  bool loading = true;

  @override
  void initState() {
    super.initState();
    search.addListener(() => setState(() {}));
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final data = jsonDecode(prefs.getString('notebook_notes') ?? '[]') as List;
      notes.addAll(data.map((e) => Note.fromJson(e)));
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notebook_notes', jsonEncode(notes.map((n) => n.toJson()).toList()));
  }

  List<Note> get filtered {
    final q = search.text.trim().toLowerCase();
    final result = notes.where((n) => n.title.toLowerCase().contains(q) || n.body.toLowerCase().contains(q)).toList();
    result.sort((a, b) => b.updated.compareTo(a.updated));
    return result;
  }

  Future<void> edit([Note? note]) async {
    final title = TextEditingController(text: note?.title ?? '');
    final body = TextEditingController(text: note?.body ?? '');
    final result = await Navigator.push<Note>(context, MaterialPageRoute(
      builder: (_) => EditorPage(title: title, body: body),
    ));
    title.dispose(); body.dispose();
    if (result == null) return;
    setState(() {
      final i = notes.indexWhere((n) => n.id == result.id);
      if (i < 0) { notes.add(result); } else { notes[i] = result; }
    });
    await persist();
  }

  Future<void> remove(Note note) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('حذف یادداشت؟'),
      content: const Text('این یادداشت حذف خواهد شد.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
      ],
    ));
    if (yes == true) { setState(() => notes.removeWhere((n) => n.id == note.id)); await persist(); }
  }

  String date(DateTime d) => '${d.toLocal().year}/${d.toLocal().month.toString().padLeft(2, '0')}/${d.toLocal().day.toString().padLeft(2, '0')}';

  @override
  void dispose() { search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final items = filtered;
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: AppBar(
        title: const Text('دفترچه یادداشت', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: () => edit(), icon: const Icon(Icons.add_rounded))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => edit(),
        icon: const Icon(Icons.edit_note_rounded),
        label: const Text('یادداشت جدید'),
      ),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 18), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ایده‌هایت را اینجا ثبت کن ✨', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('${notes.length} یادداشت در دفترچه‌ات داری', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            TextField(controller: search, decoration: InputDecoration(
              hintText: 'جستجو در یادداشت‌ها...', prefixIcon: const Icon(Icons.search),
              suffixIcon: search.text.isEmpty ? null : IconButton(onPressed: search.clear, icon: const Icon(Icons.close)),
              filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            )),
          ],
        )),
        Expanded(child: loading ? const Center(child: CircularProgressIndicator()) :
          items.isEmpty ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(search.text.isEmpty ? Icons.menu_book_rounded : Icons.search_off, size: 64, color: const Color(0xFF9B8CCB)),
            const SizedBox(height: 12),
            Text(search.text.isEmpty ? 'دفترچه‌ات هنوز خالی است' : 'یادداشتی پیدا نشد', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(search.text.isEmpty ? 'اولین یادداشتت را بنویس.' : 'عبارت دیگری را جستجو کن.'),
            if (search.text.isEmpty) ...[const SizedBox(height: 14), FilledButton(onPressed: () => edit(), child: const Text('نوشتن اولین یادداشت'))],
          ])) : ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final n = items[i];
              return Card(elevation: 0, color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: InkWell(borderRadius: BorderRadius.circular(18), onTap: () => edit(n), child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(n.title.isEmpty ? 'بدون عنوان' : n.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                      IconButton(visualDensity: VisualDensity.compact, onPressed: () => remove(n), icon: const Icon(Icons.delete_outline, color: Colors.grey)),
                    ]),
                    if (n.body.isNotEmpty) Text(n.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(height: 1.6, color: Colors.grey.shade700)),
                    const SizedBox(height: 8),
                    Text(date(n.updated), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ]),
                )),
              );
            },
          ),
        ),
      ])),
    ));
  }
}

class EditorPage extends StatelessWidget {
  final TextEditingController title, body;
  const EditorPage({super.key, required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(
    appBar: AppBar(title: const Text('یادداشت'), actions: [
      TextButton.icon(onPressed: () {
        if (title.text.trim().isEmpty && body.text.trim().isEmpty) { Navigator.pop(context); return; }
        Navigator.pop(context, Note(
          DateTime.now().microsecondsSinceEpoch.toString(), title.text.trim(), body.text.trim(), DateTime.now(),
        ));
      }, icon: const Icon(Icons.check), label: const Text('ذخیره')),
      const SizedBox(width: 8),
    ]),
    body: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      TextField(controller: title, autofocus: true, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        decoration: const InputDecoration(hintText: 'عنوان یادداشت', border: InputBorder.none)),
      const SizedBox(height: 12),
      Expanded(child: TextField(controller: body, expands: true, maxLines: null, keyboardType: TextInputType.multiline,
        textAlignVertical: TextAlignVertical.top, decoration: const InputDecoration(hintText: 'از اینجا شروع به نوشتن کن...', border: InputBorder.none))),
    ])),
  ));
}
