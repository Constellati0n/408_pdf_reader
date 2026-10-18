import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app_theme.dart';
import 'home_page.dart';
import 'models.dart';
import 'pdf_files.dart';
import 'platform_service.dart';
import 'reader_page.dart';
import 'store.dart';
import 'toc.dart';
import 'utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Required because PdfDocumentRefs may be resolved before any widget builds.
  pdfrxFlutterInitialize();
  await AppStore.instance.load();
  await TocRepository.loadCatalog();
  runApp(const ZtPdfReaderApp());
}

class ZtPdfReaderApp extends StatefulWidget {
  const ZtPdfReaderApp({super.key});

  @override
  State<ZtPdfReaderApp> createState() => _ZtPdfReaderAppState();
}

class _ZtPdfReaderAppState extends State<ZtPdfReaderApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  String? _lastHandledPath;
  DateTime? _lastHandledAt;
  String? _lastHandledLink;
  DateTime? _lastHandledLinkAt;

  @override
  void initState() {
    super.initState();
    AppStore.instance.addListener(_onStoreChanged);
    PlatformService.setHandlers(
      onFile: _handleIncomingFile,
      onDeepLink: _handleDeepLink,
    );
    unawaited(_handleInitialFile());
    unawaited(_handleInitialDeepLink());
  }

  @override
  void dispose() {
    AppStore.instance.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _handleInitialFile() async {
    final String? path = await PlatformService.initialFile();
    if (path != null) {
      await _handleIncomingFile(path);
    }
  }

  Future<void> _handleInitialDeepLink() async {
    final DeepLink? link = await PlatformService.initialDeepLink();
    if (link != null) {
      _handleDeepLink(link);
    }
  }

  /// Opens a PDF handed over by the Android activity (file manager / share).
  Future<void> _handleIncomingFile(String path) async {
    final DateTime now = DateTime.now();
    if (_lastHandledPath == path &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!).inSeconds < 5) {
      return;
    }
    _lastHandledPath = path;
    _lastHandledAt = now;
    try {
      final String localPath =
          await PdfImporter.importLocalFile(path, basename(path));
      _pushReader(localPath, pdfTitle(localPath));
    } catch (_) {
      // Unreadable hand-offs are silently ignored.
    }
  }

  /// Handles a `zt408os://` jump produced by the 408os.cn website.
  void _handleDeepLink(DeepLink link) {
    final DateTime now = DateTime.now();
    final String signature = '${link.bookCode}|${link.page}|${link.highlight}';
    if (_lastHandledLink == signature &&
        _lastHandledLinkAt != null &&
        now.difference(_lastHandledLinkAt!).inSeconds < 5) {
      return;
    }
    _lastHandledLink = signature;
    _lastHandledLinkAt = now;
    unawaited(_openDeepLink(link));
  }

  /// Opens the local copy bound to the website's book code, asking the user to
  /// pick one the first time that code shows up.
  Future<void> _openDeepLink(DeepLink link) async {
    final ShelfBook? bound = AppStore.instance.bookForCode(link.bookCode);
    if (bound != null) {
      _openBoundBook(bound, link);
      return;
    }
    final BuildContext? context = await _waitForContext();
    if (context == null || !context.mounted) return;
    final ShelfBook? chosen = await showDialog<ShelfBook>(
      context: context,
      builder: (BuildContext context) =>
          _BindBookDialog(link: link, shelf: AppStore.instance.shelf),
    );
    if (chosen == null) return;
    await AppStore.instance.bindBook(chosen.path, link.bookCode);
    final ShelfBook? updated = AppStore.instance.bookForCode(link.bookCode);
    if (updated != null) {
      _openBoundBook(updated, link);
    }
  }

  /// Jumps to the page the website asked for, corrected by the offset the user
  /// set for this particular copy.
  void _openBoundBook(ShelfBook book, DeepLink link) {
    final bool hasPage = link.page > 1;
    _pushReader(
      book.path,
      book.title,
      initialPage: hasPage ? link.page + book.webOffset : book.page,
      highlight: link.highlight,
      webPage: hasPage ? link.page : 0,
    );
  }

  /// The widget tree exists only after the first frame, so a link arriving at
  /// cold start has to wait for a usable [BuildContext] before it can prompt.
  Future<BuildContext?> _waitForContext() async {
    for (int attempt = 0; attempt < 20; attempt++) {
      final BuildContext? context = _navigatorKey.currentContext;
      if (context != null && context.mounted) return context;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }

  void _pushReader(
    String path,
    String title, {
    int initialPage = 1,
    String highlight = '',
    int webPage = 0,
  }) {
    final NavigatorState? navigator = _navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _pushReader(
          path,
          title,
          initialPage: initialPage,
          highlight: highlight,
          webPage: webPage,
        ),
      );
      return;
    }
    navigator.push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ReaderPage(
          filePath: path,
          title: title,
          initialPage: initialPage,
          initialHighlight: highlight,
          webPage: webPage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '408真题系统',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: AppStore.instance.themeMode,
      home: const HomePage(),
    );
  }
}

/// Shown the first time the website requests a book code no local PDF has
/// claimed yet: the user points the code at one of the files on their shelf.
class _BindBookDialog extends StatelessWidget {
  const _BindBookDialog({required this.link, required this.shelf});

  final DeepLink link;
  final List<ShelfBook> shelf;

  @override
  Widget build(BuildContext context) {
    final String name = TocRepository.labelFor(link.bookCode);
    return AlertDialog(
      title: const Text('选择要打开的电子书'),
      content: SizedBox(
        width: double.maxFinite,
        child: shelf.isEmpty
            ? const Text(
                '书架上还没有 PDF。请先在首页「添加电子书到书架」，'
                '把它绑定到对应教材，再回到网站重新点一次「打开教材」。',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '网站要打开《$name》第 ${link.page} 页。'
                    '请选出你本地的这本书，之后会自动记住这个绑定；'
                    '若页码对不上，可在阅读页「目录 → 网页跳转偏移」微调。',
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView(
                      shrinkWrap: true,
                      children: shelf
                          .map(
                            (ShelfBook book) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.picture_as_pdf_outlined),
                              title: Text(
                                book.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(TocRepository.labelFor(book.subject)),
                              onTap: () => Navigator.of(context).pop(book),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
