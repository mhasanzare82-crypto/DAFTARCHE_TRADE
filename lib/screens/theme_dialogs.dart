import 'package:flutter/material.dart';
import '../models/note.dart';

class ThemeManagerResult {
  final List<NoteTheme> themes;
  final List<String> randomThemeNames;
  final List<int> textColorPalette;
  final String appFontFamily;
  final String appThemeName;
  const ThemeManagerResult(this.themes, this.randomThemeNames, this.textColorPalette, this.appFontFamily, this.appThemeName);
}

class ThemeManagerDialog extends StatefulWidget {
  final List<NoteTheme> initialThemes;
  final String appFontFamily;
  final String appThemeName;
  final List<String> initialRandomThemeNames;
  final List<int> initialTextColorPalette;
  const ThemeManagerDialog({
    super.key,
    required this.initialThemes,
    this.appFontFamily = 'system-default',
    this.appThemeName = 'دودی',
    this.initialRandomThemeNames = const [],
    this.initialTextColorPalette = const [],
  });
  @override
  State<ThemeManagerDialog> createState() => _ThemeManagerDialogState();
}

class _ThemeManagerDialogState extends State<ThemeManagerDialog> {
  late List<NoteTheme> items;
  late List<String> randomThemeNames;
  late List<int> textColorPalette;
  late String selectedAppFont;
  late String selectedAppTheme;
  double hue = 220, saturation = .12, brightness = .82;
  Color get selectedColor => HSVColor.fromAHSV(1, hue, saturation, brightness).toColor();
  Color readableText(Color c) => c.computeLuminance() > .42 ? const Color(0xFF211D27) : Colors.white;

  @override
  void initState() {
    super.initState();
    items = List.of(widget.initialThemes);
    randomThemeNames = widget.initialRandomThemeNames.isEmpty
        ? items.map((e) => e.name).toList()
        : List.of(widget.initialRandomThemeNames);
    textColorPalette = List.of(widget.initialTextColorPalette);
    selectedAppFont = 'Estedad';
    selectedAppTheme = widget.appThemeName;
  }


  Future<void> editTheme([NoteTheme? old]) async {
    final result = await showDialog<NoteTheme>(
      context: context,
      builder: (_) => ThemeEditorDialog(theme: old),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (old == null) { items.add(result); randomThemeNames.add(result.name); }
      else {
        final index = items.indexOf(old);
        if (index >= 0) {
          final wasEnabled = randomThemeNames.remove(old.name);
          items[index] = result;
          if (wasEnabled) randomThemeNames.add(result.name);
        }
      }
    });
  }

  Future<void> deleteTheme(NoteTheme theme) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف تم؟'),
        content: Text('تم «${theme.name}» حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() { items.remove(theme); randomThemeNames.remove(theme.name); });
    }
  }

  void addBackgroundColor() {
    final value = selectedColor.toARGB32();
    if (items.any((e) => e.backgroundColor == value)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('این رنگ از قبل در پالت هست.')));
      return;
    }
    setState(() {
      final name = 'رنگ ${items.length + 1}';
      items.add(NoteTheme(name, value, readableText(selectedColor).toARGB32(), 'sans-serif'));
      randomThemeNames.add(name);
    });
  }

  void addTextColor() {
    final value = selectedColor.toARGB32();
    if (textColorPalette.contains(value)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('این رنگ از قبل در پالت متن هست.')));
      return;
    }
    setState(() => textColorPalette.add(value));
  }

  Widget _section(String title, IconData icon, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
        const SizedBox(height: 10),
        ...children,
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      child: SizedBox(
        width: 540,
        height: MediaQuery.sizeOf(context).height * .88,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
            child: Row(children: [
              const Expanded(child: Text('تنظیمات و شخصی‌سازی', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(child: ListView(padding: const EdgeInsets.all(14), children: [
            _section('۱. فونت رابط کاربری', Icons.font_download_outlined, [
              const Text('فونت منوها، عنوان‌ها و دکمه‌های برنامه را انتخاب کن.', style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 10),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.check_circle, color: Colors.green),
                title: Text('استعداد (Estedad)'),
                subtitle: Text('تنها فونت رابط کاربری برنامه'),
              ),
            ]),
            _section('۲. تم اصلی برنامه', Icons.contrast_outlined, [
              const Text('تم کلی محیط برنامه مستقل از رنگ‌بندی تک‌تک یادداشت‌هاست.', style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: ['سفید', 'سیاه', 'دودی', 'نقره‌ای'].contains(selectedAppTheme) ? selectedAppTheme : 'دودی',
                decoration: const InputDecoration(labelText: 'پوسته برنامه', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'سفید', child: Text('سفید')),
                  DropdownMenuItem(value: 'سیاه', child: Text('سیاه')),
                  DropdownMenuItem(value: 'دودی', child: Text('دودی')),
                  DropdownMenuItem(value: 'نقره‌ای', child: Text('نقره‌ای')),
                ],
                onChanged: (v) { if (v != null) setState(() => selectedAppTheme = v); },
              ),
            ]),
            _section('۳. رنگ‌ساز و پالت‌ها', Icons.palette_outlined, [
              const Text('رنگ را با سه کنترل HSV تنظیم کن و به پالت پس‌زمینه یا متن اضافه کن.', style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 8),
              _slider('ته‌رنگ', hue, 0, 360, (v) => setState(() => hue = v), hue.round().toString()),
              _slider('اشباع', saturation, 0, 1, (v) => setState(() => saturation = v), '${(saturation * 100).round()}٪'),
              _slider('روشنایی', brightness, 0, 1, (v) => setState(() => brightness = v), '${(brightness * 100).round()}٪'),
              Container(height: 48, decoration: BoxDecoration(color: selectedColor, borderRadius: BorderRadius.circular(12)), alignment: Alignment.center, child: Text('پیش‌نمایش رنگ', style: TextStyle(color: readableText(selectedColor), fontWeight: FontWeight.bold))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                FilledButton.tonalIcon(onPressed: addBackgroundColor, icon: const Icon(Icons.wallpaper_outlined), label: const Text('افزودن پس‌زمینه')),
                OutlinedButton.icon(onPressed: addTextColor, icon: const Icon(Icons.format_color_text), label: const Text('افزودن رنگ متن')),
              ]),
              const Divider(height: 24),
              Row(children: [
                Expanded(child: Text('پالت پس‌زمینه (${items.length})', style: const TextStyle(fontWeight: FontWeight.w600))),
                TextButton(onPressed: items.isEmpty ? null : () => setState(() { items.clear(); randomThemeNames.clear(); }), child: const Text('پاک‌کردن')),
              ]),
              if (items.isEmpty) const Text('پالت پس‌زمینه خالی است.')
              else Wrap(spacing: 8, runSpacing: 8, children: items.map((t) => Tooltip(
                message: '${t.name} — برای حذف لمس طولانی',
                child: GestureDetector(
                  onLongPress: () => deleteTheme(t),
                  child: FilterChip(
                    selected: randomThemeNames.contains(t.name),
                    label: Text(t.name, style: TextStyle(color: Color(t.textColor))),
                    avatar: CircleAvatar(backgroundColor: Color(t.backgroundColor)),
                    onSelected: (v) => setState(() { if (v) { if (!randomThemeNames.contains(t.name)) randomThemeNames.add(t.name); } else { randomThemeNames.remove(t.name); } }),
                  ),
                ),
              )).toList()),
              const SizedBox(height: 6),
              const Text('انتخاب هر تم مشخص می‌کند در تخصیص تصادفی به یادداشت‌های جدید استفاده شود. لمس طولانی برای حذف.', style: TextStyle(fontSize: 11, color: Colors.black54)),
              Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => editTheme(), icon: const Icon(Icons.add), label: const Text('ساخت تم با رنگ متن و فونت اختصاصی'))),
              const Divider(height: 24),
              Row(children: [
                Expanded(child: Text('پالت رنگ متن (${textColorPalette.length})', style: const TextStyle(fontWeight: FontWeight.w600))),
                TextButton(onPressed: textColorPalette.isEmpty ? null : () => setState(textColorPalette.clear), child: const Text('پاک‌کردن')),
              ]),
              if (textColorPalette.isEmpty) const Text('هنوز رنگ متنی اضافه نشده است.')
              else Wrap(spacing: 8, runSpacing: 8, children: List.generate(textColorPalette.length, (i) => GestureDetector(
                onLongPress: () => setState(() => textColorPalette.removeAt(i)),
                child: Container(width: 38, height: 38, decoration: BoxDecoration(color: Color(textColorPalette[i]), shape: BoxShape.circle, border: Border.all(color: Colors.black26)), child: Icon(Icons.format_color_text, size: 17, color: Color(textColorPalette[i]).computeLuminance() > .42 ? Colors.black : Colors.white)),
              ))),
              const Text('برای حذف رنگ متن، انگشت را روی آن نگه دار.', style: TextStyle(fontSize: 11, color: Colors.black54)),
            ]),
            _section('۴. مدیریت تم‌های اختصاصی یادداشت', Icons.style_outlined, [
              if (items.isEmpty) const Text('هنوز تمی ساخته نشده است.'),
              ...items.map((theme) => Card(
                color: Color(theme.backgroundColor),
                child: ListTile(
                  title: Text(theme.name, style: TextStyle(color: Color(theme.textColor), fontFamily: theme.fontFamily)),
                  subtitle: Text('پس‌زمینه، رنگ متن و فونت', style: TextStyle(color: Color(theme.textColor).withOpacity(.75))),
                  leading: Icon(Icons.text_fields, color: Color(theme.textColor)),
                  trailing: Wrap(children: [
                    IconButton(onPressed: () => editTheme(theme), icon: Icon(Icons.edit_outlined, color: Color(theme.textColor))),
                    IconButton(onPressed: () => deleteTheme(theme), icon: Icon(Icons.delete_outline, color: Color(theme.textColor))),
                  ]),
                ),
              )),
              OutlinedButton.icon(onPressed: () => editTheme(), icon: const Icon(Icons.add), label: const Text('ساخت تم جدید')),
            ]),
          ])),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, ThemeManagerResult(List.of(items), List.of(randomThemeNames), List.of(textColorPalette), selectedAppFont, selectedAppTheme)),
              icon: const Icon(Icons.save_outlined),
              label: const Text('ذخیره تنظیمات'),
            ),
          ])),
        ]),
      ),
    ),
  );

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> changed, String text) => Row(children: [
    SizedBox(width: 62, child: Text(label, style: const TextStyle(fontSize: 12))),
    Expanded(child: Slider(value: value, min: min, max: max, onChanged: changed)),
    SizedBox(width: 42, child: Text(text, textAlign: TextAlign.left, style: const TextStyle(fontSize: 11))),
  ]);
}

class ThemeEditorDialog extends StatefulWidget {
  final NoteTheme? theme;
  final List<String> customFonts;

  const ThemeEditorDialog({
    super.key,
    this.theme,
    this.customFonts = const [],
  });

  @override
  State<ThemeEditorDialog> createState() => _ThemeEditorDialogState();
}

class _ThemeEditorDialogState extends State<ThemeEditorDialog> {
  late final TextEditingController name;
  late final TextEditingController font;
  late int background;
  late int textColor;

  static const backgrounds = [
    0xFFFFEBEE, 0xFFFCE4EC, 0xFFF3E5F5, 0xFFEDE7F6, 0xFFE8EAF6,
    0xFFE3F2FD, 0xFFE1F5FE, 0xFFE0F7FA, 0xFFE0F2F1, 0xFFE8F5E9,
    0xFFF1F8E9, 0xFFF9FBE7, 0xFFFFFDE7, 0xFFFFF8E1, 0xFFFFF3E0,
    0xFFFFEAD5, 0xFFFBE9E7, 0xFFEFEBE9, 0xFFECEFF1, 0xFFE0E0E0,
    0xFFCFD8DC, 0xFFB3E5FC, 0xFFB2DFDB, 0xFFC8E6C9, 0xFFDCEDC8,
    0xFFFFF9C4, 0xFFFFE0B2, 0xFFFFCCBC, 0xFFD7CCC8, 0xFFD1C4E9,
  ];

  static const textColors = [
    0xFF16131C, 0xFF000000, 0xFF263238, 0xFF37474F, 0xFF1A237E,
    0xFF0D47A1, 0xFF006064, 0xFF004D40, 0xFF1B5E20, 0xFF33691E,
    0xFF827717, 0xFF5D4037, 0xFF4E342E, 0xFF6D4C41, 0xFF880E4F,
    0xFFAD1457, 0xFF6A1B9A, 0xFF4527A0, 0xFFB71C1C, 0xFFFFFFFF,
  ];

  static const commonFonts = ['Estedad'];

  @override
  void initState() {
    super.initState();
    final theme = widget.theme;
    name = TextEditingController(text: theme?.name ?? '');
    font = TextEditingController(text: theme?.fontFamily ?? 'Estedad');
    background = theme?.backgroundColor ?? backgrounds[3];
    textColor = theme?.textColor ?? textColors.first;
  }

  void _setColorChannel(bool isBackground, int channel, double value) {
    final current = Color(isBackground ? background : textColor);
    final channels = [current.red, current.green, current.blue];
    channels[channel] = value.round().clamp(0, 255).toInt();
    final updated = Color.fromARGB(
      255,
      channels[0],
      channels[1],
      channels[2],
    ).value;
    setState(() {
      if (isBackground) {
        background = updated;
      } else {
        textColor = updated;
      }
    });
  }

  Widget _colorChannelSlider(
    String label,
    int channel,
    int value,
    bool isBackground,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 22,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Slider(
            min: 0,
            max: 255,
            divisions: 255,
            value: value.toDouble(),
            onChanged: (next) =>
                _setColorChannel(isBackground, channel, next),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            value.toString(),
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _colorSliders(bool isBackground) {
    final color = Color(isBackground ? background : textColor);
    return Column(
      children: [
        _colorChannelSlider('R', 0, color.red, isBackground),
        _colorChannelSlider('G', 1, color.green, isBackground),
        _colorChannelSlider('B', 2, color.blue, isBackground),
      ],
    );
  }

  @override
  void dispose() {
    name.dispose();
    font.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(widget.theme == null ? 'ساخت تم جدید' : 'ویرایش تم'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  maxLength: 24,
                  decoration: const InputDecoration(
                    labelText: 'نام دلخواه تم',
                    hintText: 'مثلاً شب آرام',
                  ),
                ),
                const SizedBox(height: 12),
                const Text('۱. رنگ پس‌زمینه (۳۰ رنگ)'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: backgrounds
                      .map(
                        (color) => GestureDetector(
                          onTap: () => setState(() => background = color),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Color(color),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: background == color
                                    ? Colors.deepPurple
                                    : Colors.black26,
                                width: background == color ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'تنظیم دقیق رنگ پس‌زمینه',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Color(background),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
                  ],
                ),
                _colorSliders(true),
                const SizedBox(height: 16),
                const Text('۲. رنگ متن'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: textColors
                      .map(
                        (color) => GestureDetector(
                          onTap: () => setState(() => textColor = color),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Color(color),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: textColor == color
                                    ? Colors.deepPurple
                                    : Colors.black26,
                                width: textColor == color ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'تنظیم دقیق رنگ متن',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Color(textColor),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
                  ],
                ),
                _colorSliders(false),
                const SizedBox(height: 16),
                const Text('۳. فونت دلخواه'),
                TextField(
                  controller: font,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'نام فونت دستگاه یا فونت برنامه',
                    hintText: 'مثلاً sans-serif',
                  ),
                ),
                const Text(
                  'برای نمایش دقیق، فونت باید روی دستگاه موجود یا به برنامه اضافه شده باشد.',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [...commonFonts, ...widget.customFonts]
                      .toSet()
                      .map(
                        (family) => ActionChip(
                          label: Text(
                            family,
                            style: TextStyle(fontFamily: family, fontSize: 11),
                          ),
                          onPressed: () => setState(() => font.text = family),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                const Text('پیش‌نمایش'),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Color(background),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'یادداشت نمونه؛ این متن با فونت و رنگ انتخابی نمایش داده می‌شود.',
                    style: TextStyle(
                      color: Color(textColor),
                      fontFamily: font.text.trim().isEmpty
                          ? 'Estedad'
                          : font.text.trim(),
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              NoteTheme(
                name.text.trim().isEmpty ? 'تم بدون نام' : name.text.trim(),
                background,
                textColor,
                font.text.trim().isEmpty ? 'sans-serif' : font.text.trim(),
              ),
            ),
            child: const Text('ذخیره تم'),
          ),
        ],
      ),
    );
  }
}
