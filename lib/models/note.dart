// Domain models for notebook content.

class Note {
  final String id, title, body;
  final DateTime updated;
  final List<String> images;
  final List<String> audios;
  final int themeColor, themeTextColor;
  final String themeFontFamily;
  final String? folderId;
  const Note(this.id, this.title, this.body, this.updated, [this.images = const [], this.themeColor = 0xFFEDE7F6, this.themeTextColor = 0xFF24212A, this.themeFontFamily = 'sans-serif', this.folderId, this.audios = const []]);
  Map<String, dynamic> toJson() => {'id':id,'title':title,'body':body,'updated':updated.toIso8601String(),'images':images,'themeColor':themeColor,'themeTextColor':themeTextColor,'themeFontFamily':themeFontFamily,'folderId':folderId,'audios':audios};
  factory Note.fromJson(Map<String,dynamic> j) => Note(j['id'],j['title'],j['body'],DateTime.parse(j['updated']),List<String>.from(j['images'] ?? const []),j['themeColor'] ?? 0xFFEDE7F6,j['themeTextColor'] ?? 0xFF24212A,j['themeFontFamily'] ?? 'sans-serif',j['folderId'] as String?,List<String>.from(j['audios'] ?? const []));
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
