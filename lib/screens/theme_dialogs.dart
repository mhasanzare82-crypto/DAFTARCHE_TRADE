import 'package:flutter/material.dart';
import '../models/note.dart';

class ThemeManagerDialog extends StatefulWidget {
  final List<NoteTheme> initialThemes;
  final List<String> customFonts;
  final String appFontFamily;
  final Future<void> Function(String)? onAppFontChanged;
  final Future<List<String>> Function()? onAddCustomFont;
  const ThemeManagerDialog({super.key, required this.initialThemes, this.customFonts = const [], this.appFontFamily = 'Estedad', this.onAppFontChanged, this.onAddCustomFont});
  @override
  State<ThemeManagerDialog> createState() => _ThemeManagerDialogState();
}
class _ThemeManagerDialogState extends State<ThemeManagerDialog> {
  late List<NoteTheme> items;
  late List<String> availableFonts;
  bool addingFont = false;
  late String selectedAppFont;
  @override
  void initState() { super.initState(); items = List.of(widget.initialThemes); availableFonts = List.of(widget.customFonts); selectedAppFont = widget.appFontFamily; }
  Future<void> addFont() async {
    if (widget.onAddCustomFont == null || addingFont) return;
    setState(() => addingFont = true);
    try {
      final updated = await widget.onAddCustomFont!();
      if (mounted) setState(() => availableFonts = List.of(updated));
    } finally {
      if (mounted) setState(() => addingFont = false);
    }
  }
  Future<void> editTheme([NoteTheme? old]) async {
    final result = await showDialog<NoteTheme>(context: context, builder: (_) => ThemeEditorDialog(theme: old, customFonts: availableFonts));
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
          child: ListView(
                  shrinkWrap: true,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.text_fields, size: 20),
                                SizedBox(width: 8),
                                Text('فونت برنامه', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'فونت دلخواهت را اضافه کن و برای نمایش نوشته‌های برنامه انتخابش کن.',
                              style: TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                            const SizedBox(height: 12),
                            ...['Estedad', ...availableFonts].toSet().map((family) {
                              final displayName = family == 'Estedad'
                                  ? 'استعداد (Estedad)'
                                  : family.replaceFirst(RegExp(r'^custom_'), '').replaceFirst(RegExp(r'_\\d+
                    if (items.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('هنوز تمی نساخته‌ای.')),
                    ...items.map((theme) => Card(
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
                  )),
                  ],
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
  final List<String> customFonts;
  const ThemeEditorDialog({super.key,this.theme,this.customFonts=const []});
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
  static const commonFonts=['Estedad'];
  @override
  void initState(){
    super.initState();
    final t=widget.theme;
    name=TextEditingController(text:t?.name??'');
    font=TextEditingController(text:t?.fontFamily??'Estedad');
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
        Wrap(spacing:6,children:[...commonFonts,...widget.customFonts].map((f)=>ActionChip(label:Text(f,style:TextStyle(fontFamily:f,fontSize:11)),onPressed:()=>setState(()=>font.text=f))).toList()),
        const SizedBox(height:16),const Text('پیش‌نمایش'),
        Container(width:double.infinity,padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:Color(background),borderRadius:BorderRadius.circular(12)),child:Text('یادداشت نمونه؛ این متن با فونت و رنگ انتخابی نمایش داده می‌شود.',style:TextStyle(color:Color(textColor),fontFamily:font.text.trim().isEmpty?'Estedad':font.text.trim(),fontSize:16))),
      ],
    ))),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(context),child:const Text('انصراف')),
      FilledButton(onPressed:()=>Navigator.pop(context,NoteTheme(name.text.trim().isEmpty?'تم بدون نام':name.text.trim(),background,textColor,font.text.trim().isEmpty?'sans-serif':font.text.trim())),child:const Text('ذخیره تم')),
    ],
  ));
}

), '').replaceAll('_', ' ');
                              final selected = selectedAppFont == family;
                              return Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 9),
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                                    width: selected ? 1.8 : 1,
                                  ),
                                  color: selected ? Theme.of(context).colorScheme.primary.withOpacity(.06) : null,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(child: Text(displayName, style: const TextStyle(fontWeight: FontWeight.w600))),
                                        if (selected) const Icon(Icons.check_circle, color: Colors.green, size: 19),
                                        const SizedBox(width: 8),
                                        OutlinedButton(
                                          onPressed: selected ? null : () async {
                                            setState(() => selectedAppFont = family);
                                            await widget.onAppFontChanged?.call(family);
                                          },
                                          child: Text(selected ? 'انتخاب شده' : 'انتخاب فونت'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 7),
                                    Text(
                                      'نمونه فونت',
                                      style: TextStyle(fontFamily: family, fontSize: 21, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'متن‌های برنامه، عنوان‌ها و دکمه‌ها با این فونت نمایش داده می‌شوند.',
                                      style: TextStyle(fontFamily: family, fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: addingFont ? null : addFont,
                                icon: addingFont
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.add),
                                label: Text(addingFont ? 'در حال افزودن فونت...' : 'افزودن فونت جدید (TTF / OTF)'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (items.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('هنوز تمی نساخته‌ای.')),
                    ...items.map((theme) => Card(
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
                  )),
                  ],
                ),
        ),
        actions: [
          TextButton.icon(
            onPressed: addingFont ? null : addFont,
            icon: addingFont
                ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2))
                : const Icon(Icons.upload_file_outlined),
            label: Text(addingFont ? 'در حال افزودن...' : 'افزودن فونت'),
          ),
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
  final List<String> customFonts;
  const ThemeEditorDialog({super.key,this.theme,this.customFonts=const []});
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
  static const commonFonts=['Estedad'];
  @override
  void initState(){
    super.initState();
    final t=widget.theme;
    name=TextEditingController(text:t?.name??'');
    font=TextEditingController(text:t?.fontFamily??'Estedad');
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
        Wrap(spacing:6,children:[...commonFonts,...widget.customFonts].map((f)=>ActionChip(label:Text(f,style:TextStyle(fontFamily:f,fontSize:11)),onPressed:()=>setState(()=>font.text=f))).toList()),
        const SizedBox(height:16),const Text('پیش‌نمایش'),
        Container(width:double.infinity,padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:Color(background),borderRadius:BorderRadius.circular(12)),child:Text('یادداشت نمونه؛ این متن با فونت و رنگ انتخابی نمایش داده می‌شود.',style:TextStyle(color:Color(textColor),fontFamily:font.text.trim().isEmpty?'Estedad':font.text.trim(),fontSize:16))),
      ],
    ))),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(context),child:const Text('انصراف')),
      FilledButton(onPressed:()=>Navigator.pop(context,NoteTheme(name.text.trim().isEmpty?'تم بدون نام':name.text.trim(),background,textColor,font.text.trim().isEmpty?'sans-serif':font.text.trim())),child:const Text('ذخیره تم')),
    ],
  ));
}

