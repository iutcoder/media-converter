import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'src/converter.dart';

void main() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'libwebp',
    ], await rootBundle.loadString('assets/licenses/libwebp.txt'));
  });
  runApp(const WebpStudio());
}

class WebpStudio extends StatelessWidget {
  const WebpStudio({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'WebP Studio',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFB9ED80),
        brightness: Brightness.dark,
        primary: const Color(0xFFB9ED80),
        surface: const Color(0xFF171C22),
      ),
      scaffoldBackgroundColor: const Color(0xFF101419),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      cardTheme: const CardThemeData(margin: EdgeInsets.zero),
    ),
    home: const StudioPage(),
  );
}

/// 원본 경로는 바꾸지 않는다. 이름 변경은 저장될 WebP 이름에만 적용한다.
class ImageEntry {
  final String path;
  final int inputBytes;
  EncodeOptions? override;
  String status = '대기';
  String? savedPath;
  ImageEntry(this.path, this.inputBytes);
}

class StudioPage extends StatefulWidget {
  const StudioPage({super.key});
  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  final entries = <ImageEntry>[];
  // Finder가 부여한 접근 권한은 앱 세션 동안 유지하고 종료 시 반환한다.
  final scopes = <Uint8List>[];
  final prefix = TextEditingController();
  String? folder;
  EncodeOptions options = const EncodeOptions();
  int start = 1, digits = 3, completed = 0;
  bool busy = false, importing = false, cancel = false, hovering = false;
  String summary = 'PNG 이미지를 추가해 시작하세요.';

  @override
  void dispose() {
    for (final bookmark in scopes) {
      DesktopDrop.instance.stopAccessingSecurityScopedResource(
        bookmark: bookmark,
      );
    }
    prefix.dispose();
    super.dispose();
  }

  void notify(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> receiveDrop(DropDoneDetails details) async {
    if (busy || importing) return;
    try {
      for (final file in details.files) {
        final bookmark = file.extraAppleBookmark;
        if (Platform.isMacOS &&
            bookmark != null &&
            await DesktopDrop.instance.startAccessingSecurityScopedResource(
              bookmark: bookmark,
            )) {
          scopes.add(bookmark);
        }
      }
      await addFiles(details.files.map((f) => f.path));
    } catch (e) {
      notify('드롭한 파일에 접근하지 못했습니다: $e');
    }
  }

  Future<void> pickFiles() async {
    try {
      final files = await openFiles(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'PNG 이미지', extensions: ['png']),
        ],
      );
      await addFiles(files.map((f) => f.path));
    } catch (e) {
      notify('파일을 불러오지 못했습니다: $e');
    }
  }

  Future<void> addFiles(Iterable<String> paths) async {
    if (busy || importing) return;
    setState(() => importing = true);
    var ignored = 0;
    final known = entries.map((e) => e.path).toSet();
    final additions = <ImageEntry>[];
    for (final path in paths) {
      try {
        if (p.extension(path).toLowerCase() != '.png' ||
            !await File(path).exists()) {
          ignored++;
          continue;
        }
        final canonical = await File(path).resolveSymbolicLinks();
        if (!known.add(canonical)) {
          ignored++;
          continue;
        }
        additions.add(ImageEntry(canonical, await File(canonical).length()));
      } catch (_) {
        ignored++;
      }
    }
    if (!mounted) return;
    setState(() {
      entries.addAll(additions);
      importing = false;
      summary = '${entries.length}개의 이미지 • 드래그해서 저장 순서를 바꿀 수 있습니다.';
    });
    if (ignored > 0) notify('중복 파일, 폴더 또는 PNG가 아닌 항목 $ignored개를 제외했습니다.');
  }

  Future<void> pickFolder() async {
    try {
      final value = await getDirectoryPath(
        initialDirectory: folder,
        confirmButtonText: '여기에 저장',
        canCreateDirectories: true,
      );
      if (value != null && mounted) setState(() => folder = value);
    } catch (e) {
      notify('폴더를 선택하지 못했습니다: $e');
    }
  }

  String nameAt(int index) => outputName(
    entries[index].path,
    index,
    prefix: prefix.text,
    start: start,
    digits: digits,
  );

  Future<void> editOptions(ImageEntry entry) async {
    final result = await showDialog<EncodeOptions>(
      context: context,
      builder: (context) {
        var draft = entry.override ?? options;
        return StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('이 이미지의 변환 옵션'),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: OptionsEditor(
                  value: draft,
                  onChanged: (v) => update(() => draft = v),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() => entry.override = null);
                  Navigator.pop(context);
                },
                child: const Text('공통 옵션 사용'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, draft),
                child: const Text('적용'),
              ),
            ],
          ),
        );
      },
    );
    if (result != null && mounted) setState(() => entry.override = result);
  }

  Future<void> convert() async {
    if (busy || entries.isEmpty || folder == null) return;
    setState(() {
      busy = true;
      cancel = false;
      completed = 0;
      summary = '변환 준비 중…';
    });
    var success = 0, failed = 0;
    // 작업 시작 시 이름과 설정을 확정한다. 인코딩 중에는 UI 편집을 잠근다.
    final jobs = [
      for (var i = 0; i < entries.length; i++)
        (
          entry: entries[i],
          name: nameAt(i),
          options: entries[i].override ?? options,
        ),
    ];
    final outputDirectory = folder!;
    for (final job in jobs) {
      job.entry.status = '대기';
      job.entry.savedPath = null;
    }
    for (final job in jobs) {
      if (cancel) break;
      setState(() {
        job.entry.status = '변환 중…';
        summary = '${completed + 1} / ${jobs.length} 변환 중';
      });
      try {
        // 전체 화면 상태를 isolate로 보내지 않고 필요한 값만 캡처한다.
        final source = job.entry.path, name = job.name;
        final settings = job.options;
        final result = await convertPngAsync(
          source,
          outputDirectory,
          name,
          settings,
        );
        job.entry.savedPath = result.path;
        job.entry.status =
            '완료 · ${formatBytes(result.bytes)}'
            ' · EXIF/XMP 제거'
            '${result.stealthRemoved ? ' · 숨김 정보 정리' : ''}';
        success++;
      } catch (e) {
        job.entry.status = '실패 · $e';
        failed++;
      }
      if (!mounted) return;
      setState(() => completed++);
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      summary =
          '${cancel ? '중단됨' : '변환 완료'} · 성공 $success개 / 실패 $failed개'
          '${cancel ? ' / 남은 ${jobs.length - completed}개' : ''}';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Color(0xFF172010),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WebP Studio',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '가볍게 바꾸고, 깔끔하게 정리하세요.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                const Chip(label: Text('PNG → WebP')),
                IconButton(
                  tooltip: '앱 정보 및 라이선스',
                  onPressed: () => showAboutDialog(
                    context: context,
                    applicationName: 'WebP Studio',
                    applicationVersion: '0.1.3',
                    children: [const Text('Flutter + C++ · PNG → WebP 변환')],
                  ),
                  icon: const Icon(Icons.info_outline),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = settingsPanel();
                  if (constraints.maxWidth < 760) {
                    return Column(
                      children: [
                        Expanded(child: filePanel()),
                        const SizedBox(height: 12),
                        SizedBox(height: 260, child: side),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: filePanel()),
                      const SizedBox(width: 22),
                      SizedBox(width: 320, child: side),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            if (busy)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(
                  value: entries.isEmpty ? 0 : completed / entries.length,
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    summary,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                if (busy)
                  OutlinedButton(
                    onPressed: cancel
                        ? null
                        : () => setState(() {
                            cancel = true;
                            summary = '현재 이미지 완료 후 중단합니다…';
                          }),
                    child: Text(cancel ? '중단 요청됨' : '중단'),
                  )
                else
                  FilledButton.icon(
                    onPressed: entries.isEmpty || folder == null || importing
                        ? null
                        : convert,
                    icon: const Icon(Icons.bolt),
                    label: Text('${entries.length}개 변환하기'),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget filePanel() => DropTarget(
    enable: !busy && !importing,
    onDragEntered: (_) => setState(() => hovering = true),
    onDragExited: (_) => setState(() => hovering = false),
    onDragDone: (details) {
      setState(() => hovering = false);
      receiveDrop(details);
    },
    child: Container(
      decoration: BoxDecoration(
        color: hovering ? const Color(0xFF263226) : const Color(0xFF171C22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hovering ? const Color(0xFFB9ED80) : Colors.white10,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '이미지  ${entries.length}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: busy || importing || entries.isEmpty
                      ? null
                      : () => setState(() {
                          entries.clear();
                          summary = 'PNG 이미지를 추가해 시작하세요.';
                        }),
                  child: const Text('비우기'),
                ),
                OutlinedButton.icon(
                  onPressed: busy || importing ? null : pickFiles,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('파일 추가'),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 62,
                            color: Color(0xFFB9ED80),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'PNG 파일을 여기에 놓으세요',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '여러 파일을 한 번에 추가할 수 있습니다.',
                            style: TextStyle(color: Colors.white54),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.tonal(
                            onPressed: importing ? null : pickFiles,
                            child: const Text('파일 찾아보기'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: entries.length,
                    buildDefaultDragHandles: false,
                    onReorderItem: (oldIndex, newIndex) {
                      if (busy) return;
                      setState(() {
                        entries.insert(newIndex, entries.removeAt(oldIndex));
                      });
                    },
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return Card(
                        key: ValueKey(entry.path),
                        margin: const EdgeInsets.only(bottom: 8),
                        color: const Color(0xFF20262D),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              ReorderableDragStartListener(
                                index: index,
                                enabled: !busy,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(
                                    Icons.drag_indicator,
                                    color: Colors.white38,
                                  ),
                                ),
                              ),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(entry.path),
                                  width: 56,
                                  height: 56,
                                  cacheWidth: 112,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, error, stack) =>
                                      const SizedBox(
                                        width: 56,
                                        height: 56,
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                        ),
                                      ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.basename(entry.path),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '→ ${entry.savedPath == null ? nameAt(index) : p.basename(entry.savedPath!)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFB9ED80),
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Tooltip(
                                      message: entry.status,
                                      child: Text(
                                        '${formatBytes(entry.inputBytes)} · ${entry.status}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: entry.status.startsWith('실패')
                                              ? Colors.redAccent
                                              : Colors.white54,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: entry.override == null
                                    ? '파일별 옵션'
                                    : '개별 옵션 적용 중',
                                onPressed: busy
                                    ? null
                                    : () => editOptions(entry),
                                icon: Icon(
                                  Icons.tune,
                                  size: 19,
                                  color: entry.override == null
                                      ? Colors.white54
                                      : const Color(0xFFB9ED80),
                                ),
                              ),
                              IconButton(
                                tooltip: '목록에서 제거',
                                onPressed: busy
                                    ? null
                                    : () => setState(
                                        () => entries.removeAt(index),
                                      ),
                                icon: const Icon(Icons.close, size: 18),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'PNG 전용 · 원본 파일은 변경하지 않습니다.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );

  Widget settingsPanel() => SingleChildScrollView(
    child: AbsorbPointer(
      absorbing: busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          section('01', '일괄 이름 변경'),
          TextField(
            controller: prefix,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: '접두어 (선택)',
              hintText: '예: portfolio',
              helperText: '비워두면 번호만 사용합니다. 예: 001.webp',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: '1',
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                  ],
                  decoration: const InputDecoration(labelText: '시작 번호'),
                  onChanged: (v) =>
                      setState(() => start = int.tryParse(v) ?? 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: digits,
                  decoration: const InputDecoration(labelText: '자릿수'),
                  items: [1, 2, 3, 4, 5]
                      .map(
                        (v) => DropdownMenuItem(value: v, child: Text('$v자리')),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => digits = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          section('02', '변환 옵션'),
          OptionsEditor(
            value: options,
            onChanged: (v) => setState(() => options = v),
          ),
          const SizedBox(height: 24),
          section('03', '저장 위치'),
          OutlinedButton.icon(
            onPressed: pickFolder,
            icon: const Icon(Icons.folder_open),
            label: const Text('저장 폴더 선택'),
          ),
          const SizedBox(height: 8),
          SelectableText(
            folder ?? '아직 선택하지 않았습니다.',
            style: const TextStyle(fontSize: 12, color: Colors.white60),
          ),
          const SizedBox(height: 12),
          const Text(
            '이름이 겹치면 (1), (2)를 붙여 저장합니다.',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ],
      ),
    ),
  );

  Widget section(String number, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        Text(
          number,
          style: const TextStyle(color: Color(0xFFB9ED80), fontSize: 12),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

/// 공통 설정과 파일별 설정에서 같은 편집기를 재사용한다.
class OptionsEditor extends StatelessWidget {
  final EncodeOptions value;
  final ValueChanged<EncodeOptions> onChanged;
  const OptionsEditor({
    super.key,
    required this.value,
    required this.onChanged,
  });
  void update({
    bool? lossless,
    bool? keepColorProfile,
    double? quality,
    int? method,
    int? maxEdge,
  }) => onChanged(
    EncodeOptions(
      lossless: lossless ?? value.lossless,
      keepColorProfile: keepColorProfile ?? value.keepColorProfile,
      quality: quality ?? value.quality,
      method: method ?? value.method,
      maxEdge: maxEdge ?? value.maxEdge,
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('무손실 압축'),
        subtitle: const Text('8비트 픽셀과 투명도 보존', style: TextStyle(fontSize: 11)),
        value: value.lossless,
        onChanged: (v) => update(lossless: v),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('색상 프로필(ICC)만 보존'),
        subtitle: const Text(
          'EXIF·XMP·NAI 숨김 정보는 항상 제거\n기본값: ICC도 제거 · 투명도 최대 1/255 변경',
          style: TextStyle(fontSize: 11),
        ),
        value: value.keepColorProfile,
        onChanged: (v) => update(keepColorProfile: v),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(value.lossless ? '압축 노력' : '이미지 품질'),
          Text('${value.quality.round()}'),
        ],
      ),
      Slider(
        value: value.quality,
        min: 0,
        max: 100,
        divisions: 100,
        onChanged: (v) => update(quality: v),
      ),
      DropdownButtonFormField<int>(
        initialValue: value.method,
        decoration: const InputDecoration(labelText: '인코딩 속도'),
        items: const [
          DropdownMenuItem(value: 0, child: Text('빠르게')),
          DropdownMenuItem(value: 4, child: Text('균형 잡힌 압축')),
          DropdownMenuItem(value: 6, child: Text('더 작게 · 느림')),
        ],
        onChanged: (v) => update(method: v),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<int>(
        initialValue: value.maxEdge,
        decoration: const InputDecoration(labelText: '긴 변 최대 크기'),
        items: [0, 512, 1024, 1920, 2560, 3840]
            .map(
              (v) => DropdownMenuItem(
                value: v,
                child: Text(v == 0 ? '원본 크기' : '$v px'),
              ),
            )
            .toList(),
        onChanged: (v) => update(maxEdge: v),
      ),
      const SizedBox(height: 8),
      const Text(
        '비율을 유지하며 축소합니다. 작은 이미지는 확대하지 않습니다.',
        style: TextStyle(fontSize: 11, color: Colors.white38),
      ),
    ],
  );
}

String formatBytes(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1048576
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / 1048576).toStringAsFixed(1)} MB';
