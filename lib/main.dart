import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
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
    home: const NotesPage(),
  );
}

class Note {
  final String id, title, body;
  final DateTime updated;
  final List<String> images;
  const Note(this.id, this.title, this.body, this.updated, [this.images = const []]);
  Map<String, dynamic> toJson() => {'id':id,'title':title,'body':body,'updated':updated.toIso8601String(),'images':images};
  factory Note.fromJson(Map<String,dynamic> j) => Note(j['id'],j['title'],j['body'],DateTime.parse(j['updated']),List<String>.from(j['images'] ?? const []));
}

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});
  @override
  State<NotesPage> createState() => _NotesPageState();
}
class _NotesPageState extends State<NotesPage> {
  final notes=<Note>[];
  final search=TextEditingController();
  bool loading=true;
  @override
  void initState(){super.initState();search.addListener(()=>setState((){}));load();}
  Future<void> load() async {
    final p=await SharedPreferences.getInstance();
    try { notes.addAll((jsonDecode(p.getString('notebook_notes')??'[]') as List).map((e)=>Note.fromJson(e))); } catch(_){}
    if(mounted)setState(()=>loading=false);
  }
  Future<void> persist() async {
    final p=await SharedPreferences.getInstance();
    await p.setString('notebook_notes',jsonEncode(notes.map((n)=>n.toJson()).toList()));
  }
  List<Note> get filtered {
    final q=search.text.trim().toLowerCase();
    final list=notes.where((n)=>n.title.toLowerCase().contains(q)||n.body.toLowerCase().contains(q)).toList();
    list.sort((a,b)=>b.updated.compareTo(a.updated));return list;
  }
  Future<void> edit([Note? note]) async {
    final result=await Navigator.push<Note>(context,MaterialPageRoute(builder:(_)=>EditorPage(note:note)));
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
  String date(DateTime d)=>d.year.toString()+'/'+d.month.toString().padLeft(2,'0')+'/'+d.day.toString().padLeft(2,'0');
  @override
  void dispose(){search.dispose();super.dispose();}
  @override
  Widget build(BuildContext context){
    final items=filtered;
    return Directionality(textDirection:TextDirection.rtl,child:Scaffold(
      appBar:AppBar(title:const Text('دفترچه یادداشت',style:TextStyle(fontWeight:FontWeight.bold)),actions:[IconButton(onPressed:()=>edit(),icon:const Icon(Icons.add_rounded))]),
      floatingActionButton:FloatingActionButton.extended(onPressed:()=>edit(),icon:const Icon(Icons.edit_note_rounded),label:const Text('یادداشت جدید')),
      body:SafeArea(child:Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(20,8,20,18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('ایده‌هایت را اینجا ثبت کن ✨',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),
          const SizedBox(height:6),Text(notes.length.toString()+' یادداشت در دفترچه‌ات داری',style:TextStyle(color:Colors.grey.shade600)),
          const SizedBox(height:16),
          TextField(controller:search,decoration:InputDecoration(hintText:'جستجو در یادداشت‌ها...',prefixIcon:const Icon(Icons.search),suffixIcon:search.text.isEmpty?null:IconButton(onPressed:search.clear,icon:const Icon(Icons.close)),filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:BorderSide.none))),
        ])),
        Expanded(child:loading?const Center(child:CircularProgressIndicator()):items.isEmpty
          ?Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[const Icon(Icons.menu_book_rounded,size:64,color:Color(0xFF9B8CCB)),const SizedBox(height:12),Text(search.text.isEmpty?'دفترچه‌ات هنوز خالی است':'یادداشتی پیدا نشد',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:8),Text(search.text.isEmpty?'اولین یادداشتت را بنویس.':'عبارت دیگری را جستجو کن.'),if(search.text.isEmpty)...[const SizedBox(height:14),FilledButton(onPressed:()=>edit(),child:const Text('نوشتن اولین یادداشت'))]]))
          :ListView.separated(padding:const EdgeInsets.fromLTRB(20,0,20,100),itemCount:items.length,separatorBuilder:(_,__)=>const SizedBox(height:10),itemBuilder:(_,i){
            final n=items[i];
            return Card(elevation:0,color:Colors.white,child:InkWell(onTap:()=>edit(n),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[Expanded(child:Text(n.title.isEmpty?'بدون عنوان':n.title,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16))),IconButton(onPressed:()=>remove(n),icon:const Icon(Icons.delete_outline))]),
              if(n.body.isNotEmpty)Text(n.body,maxLines:3,overflow:TextOverflow.ellipsis),
              if(n.images.isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Text(n.images.length.toString()+' تصویر پیوست شده',style:TextStyle(color:Colors.grey.shade600,fontSize:12))),
              const SizedBox(height:8),Text(date(n.updated),style:TextStyle(fontSize:11,color:Colors.grey.shade500)),
            ]))));
          })),
      ])),
    ));
  }
}

class EditorPage extends StatefulWidget {
  final Note? note;
  const EditorPage({super.key,this.note});
  @override
  State<EditorPage> createState()=>_EditorPageState();
}
class _EditorPageState extends State<EditorPage>{
  late final TextEditingController title,body;
  final images=<String>[];
  final picker=ImagePicker();
  @override
  void initState(){super.initState();title=TextEditingController(text:widget.note?.title??'');body=TextEditingController(text:widget.note?.body??'');images.addAll(widget.note?.images??const []);}
  Future<String> copyImage(String path)async{
    final dir=await getApplicationDocumentsDirectory();
    final folder=Directory(dir.path+'/notebook_images');
    if(!await folder.exists())await folder.create(recursive:true);
    final ext=path.contains('.')?path.substring(path.lastIndexOf('.')):'.jpg';
    return (await File(path).copy(folder.path+'/'+DateTime.now().microsecondsSinceEpoch.toString()+ext)).path;
  }
  Future<void> addImage()async{
    final x=await picker.pickImage(source:ImageSource.gallery,imageQuality:90);
    if(x==null)return;
    final path=await copyImage(x.path);
    if(mounted)setState(()=>images.add(path));
  }
  Future<void> draw(int i)async{
    final path=await Navigator.push<String>(context,MaterialPageRoute(builder:(_)=>DrawingPage(imagePath:images[i])));
    if(path!=null&&mounted)setState(()=>images[i]=path);
  }
  void save(){
    if(title.text.trim().isEmpty&&body.text.trim().isEmpty&&images.isEmpty){Navigator.pop(context);return;}
    Navigator.pop(context,Note(widget.note?.id??DateTime.now().microsecondsSinceEpoch.toString(),title.text.trim(),body.text.trim(),DateTime.now(),List.of(images)));
  }
  @override
  void dispose(){title.dispose();body.dispose();super.dispose();}
  @override
  Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('یادداشت'),actions:[TextButton.icon(onPressed:save,icon:const Icon(Icons.check),label:const Text('ذخیره'))]),
    body:Padding(padding:const EdgeInsets.all(20),child:Column(children:[
      TextField(controller:title,autofocus:true,style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold),decoration:const InputDecoration(hintText:'عنوان یادداشت',border:InputBorder.none)),
      const SizedBox(height:10),
      Expanded(child:ListView(children:[
        TextField(controller:body,minLines:5,maxLines:null,keyboardType:TextInputType.multiline,decoration:const InputDecoration(hintText:'متن یادداشتت را اینجا بنویس...',border:InputBorder.none)),
        if(images.isNotEmpty)...[
          const SizedBox(height:14),const Text('تصاویر یادداشت',style:TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:8),
          for(int i=0;i<images.length;i++)Padding(padding:const EdgeInsets.only(bottom:14),child:ClipRRect(borderRadius:BorderRadius.circular(14),child:Stack(children:[
            Image.file(File(images[i]),width:double.infinity,fit:BoxFit.contain),
            Positioned(left:8,top:8,child:Row(children:[
              IconButton.filled(onPressed:()=>draw(i),icon:const Icon(Icons.draw_rounded),tooltip:'نقاشی روی عکس'),
              const SizedBox(width:5),IconButton.filled(onPressed:()=>setState(()=>images.removeAt(i)),icon:const Icon(Icons.delete_outline),tooltip:'حذف عکس'),
            ])),
          ]))),
        ],
      ])),
      SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:addImage,icon:const Icon(Icons.add_photo_alternate_outlined),label:const Text('افزودن عکس از گالری'))),
    ])),
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
