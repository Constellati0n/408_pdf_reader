import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app_theme.dart';
import 'home_page.dart';
import 'pdf_files.dart';
import 'platform_service.dart';
import 'reader_page.dart';
import 'store.dart';
import 'utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Required because PdfDocumentRefs may be resolved before any widget builds.
  pdfrxFlutterInitialize();
  await AppStore.instance.load();
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

  @override
  void initState() {
    super.initState();
    AppStore.instance.addListener(_onStoreChanged);
    PlatformService.setFileHandler(_handleIncomingFile);
    unawaited(_handleInitialFile());
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

  void _pushReader(String path, String title) {
    final NavigatorState? navigator = _navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _pushReader(path, title),
      );
      return;
    }
    navigator.push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ReaderPage(filePath: path, title: title),
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
