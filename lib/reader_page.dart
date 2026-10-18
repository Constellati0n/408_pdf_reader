import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'store.dart';
import 'toc.dart';
import 'widgets/outline_view.dart';
import 'widgets/search_bar_view.dart';
import 'widgets/thumbnails_view.dart';

/// PDF reading page: continuous scroll, zoom, outline, thumbnails, search.
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.filePath,
    required this.title,
    this.initialPage = 1,
    this.subject = kSubjectNone,
    this.pageOffset = 0,
    this.initialHighlight = '',
    this.webPage = 0,
  });

  final String filePath;
  final String title;
  final int initialPage;

  /// Curated table of contents to use, or [kSubjectNone] for the PDF's own.
  final String subject;

  /// Correction added to the curated table of contents page numbers.
  final int pageOffset;

  /// Snippet the website asked to highlight, forwarded by a `zt408os://` link.
  final String initialHighlight;

  /// Page the 408os.cn link quoted, before the web offset was applied. Zero
  /// when the book was opened normally rather than through a jump link.
  final int webPage;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final PdfViewerController _controller = PdfViewerController();
  late final PdfViewerParams _params;

  /// Created lazily: [PdfTextSearcher]'s constructor immediately dereferences
  /// the controller's document, which is only available once the viewer is
  /// attached and the document loaded. Building it in [initState] throws.
  PdfTextSearcher? _searcher;

  /// Set once the deep-link highlight has been located, so the search listener
  /// stops after the first hit.
  bool _highlightLocated = false;

  PdfDocument? _document;
  int _pageNumber = 1;
  int _pageCount = 0;
  late String _subject;
  late int _pageOffset;
  late int _webOffset;
  bool _searchVisible = false;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _pageNumber = widget.initialPage < 1 ? 1 : widget.initialPage;
    // Explicit arguments win, otherwise reuse whatever the shelf already knows
    // about this file (so "open with" lands on the same table of contents).
    _subject = widget.subject != kSubjectNone
        ? widget.subject
        : AppStore.instance.subjectOf(widget.filePath);
    _pageOffset = widget.pageOffset != 0
        ? widget.pageOffset
        : AppStore.instance.pageOffsetOf(widget.filePath);
    _webOffset = AppStore.instance.webOffsetOf(widget.filePath);
    // Built once on purpose: PdfViewerParams carries closures, and a new
    // instance on every rebuild would look "changed" to the viewer.
    _params = PdfViewerParams(
      margin: 8,
      onViewerReady: _onViewerReady,
      onPageChanged: _onPageChanged,
      pagePaintCallbacks: <PdfViewerPagePaintCallback>[_paintSearchMatches],
      matchTextColor: const Color(0x6600BAAD),
      activeMatchTextColor: const Color(0xAAFFB300),
      textSelectionParams: const PdfTextSelectionParams(),
      loadingBannerBuilder:
          (BuildContext context, int bytesDownloaded, int? totalBytes) =>
              const Center(child: CircularProgressIndicator()),
      errorBannerBuilder: (
        BuildContext context,
        Object error,
        StackTrace? stackTrace,
        PdfDocumentRef documentRef,
      ) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text('PDF 打开失败', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    unawaited(
      AppStore.instance.updatePage(widget.filePath, _pageNumber, _pageCount),
    );
    _searcher?.dispose();
    super.dispose();
  }

  /// Delegates to the text searcher when one exists, so that
  /// [PdfViewerParams.pagePaintCallbacks] can stay stable across rebuilds.
  void _paintSearchMatches(Canvas canvas, Rect pageRect, PdfPage page) {
    _searcher?.pageTextMatchPaintCallback(canvas, pageRect, page);
  }

  void _onViewerReady(PdfDocument document, PdfViewerController controller) {
    if (!mounted) return;
    setState(() {
      _document = document;
      _pageCount = controller.pageCount;
    });
    unawaited(
      AppStore.instance.addBook(
        path: widget.filePath,
        title: widget.title,
        totalPages: controller.pageCount,
      ),
    );
    _startInitialHighlight();
    if (widget.webPage > 0) _announceWebJump();
  }

  /// Tells the user which page the website asked for and where it landed, since
  /// the site quotes the textbook's printed page rather than the PDF's own, and
  /// offers the stepper to correct it. Skipped once the user has adjusted the
  /// web offset for this book, so everyday deep links stay quiet.
  void _announceWebJump() {
    if (AppStore.instance.webOffsetSetOf(widget.filePath)) return;
    final int target = widget.initialPage;
    final String signed =
        _webOffset >= 0 ? '+ $_webOffset' : '- ${-_webOffset}';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('网站第 ${widget.webPage} 页 $signed = 第 $target 页'),
          action: SnackBarAction(
            label: '调整网页偏移',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    });
  }

  /// Runs the snippet a `zt408os://` link carried, searching quietly in the
  /// background. Scanned PDFs have no text layer, so finding nothing is an
  /// expected outcome and simply leaves the requested page in place.
  void _startInitialHighlight() {
    final String text = widget.initialHighlight.trim();
    if (text.isEmpty || _highlightLocated) return;
    _searcher ??= PdfTextSearcher(_controller);
    _searcher!.addListener(_onHighlightSearchTick);
    _searcher!.startTextSearch(
      RegExp(RegExp.escape(text), caseSensitive: false),
      goToFirstMatch: false,
      searchImmediately: true,
    );
    setState(() => _searchVisible = true);
  }

  void _onHighlightSearchTick() {
    final PdfTextSearcher? searcher = _searcher;
    if (searcher == null || _highlightLocated) return;
    final ({int start, int end})? range =
        searcher.getMatchesRangeForPage(widget.initialPage < 1 ? 1 : widget.initialPage);
    if (range == null || range.end <= range.start) return;
    _highlightLocated = true;
    searcher.removeListener(_onHighlightSearchTick);
    unawaited(searcher.goToMatchOfIndex(range.start));
  }

  void _onPageChanged(int? pageNumber) {
    if (pageNumber == null || pageNumber == _pageNumber) return;
    setState(() => _pageNumber = pageNumber);
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(
        AppStore.instance.updatePage(widget.filePath, _pageNumber, _pageCount),
      );
    });
  }

  void _toggleSearch() {
    if (!_searchVisible) {
      // The viewer has to be attached before a searcher can be created.
      if (_searcher == null && _controller.isReady) {
        _searcher = PdfTextSearcher(_controller);
      }
      if (_searcher == null) return;
    }
    setState(() => _searchVisible = !_searchVisible);
    if (!_searchVisible) {
      _searcher?.resetTextSearch();
    }
  }

  Future<void> _goToPage(int pageNumber) async {
    if (_pageCount <= 0) return;
    await _controller.goToPage(pageNumber: pageNumber.clamp(1, _pageCount));
  }

  /// Stores a new table-of-contents page correction for this book.
  Future<void> _changeOffset(int offset) async {
    setState(() => _pageOffset = offset);
    await AppStore.instance.setPageOffset(widget.filePath, offset);
  }

  /// Stores a new correction for pages arriving from 408os.cn.
  Future<void> _changeWebOffset(int offset) async {
    setState(() => _webOffset = offset);
    await AppStore.instance.setWebOffset(widget.filePath, offset);
  }

  Future<void> _showJumpDialog() async {
    final TextEditingController input = TextEditingController(text: '$_pageNumber');
    final int? target = await showDialog<int>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('跳转到页'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1 - $_pageCount'),
          onSubmitted: (String value) =>
              Navigator.of(context).pop(int.tryParse(value.trim())),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(int.tryParse(input.text.trim())),
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    input.dispose();
    if (target != null) {
      await _goToPage(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PdfTextSearcher? searcher = _searcher;
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            icon: Icon(_searchVisible ? Icons.search_off : Icons.search),
            tooltip: '搜索',
            onPressed: _pageCount > 0 ? _toggleSearch : null,
          ),
          ListenableBuilder(
            listenable: AppStore.instance,
            builder: (BuildContext context, Widget? child) => IconButton(
              icon: Icon(
                AppStore.instance.invertPages
                    ? Icons.nights_stay
                    : Icons.wb_sunny_outlined,
              ),
              tooltip: '夜间反色',
              onPressed: () => AppStore.instance.toggleInvertPages(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.menu_book),
            tooltip: '目录 / 缩略图',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      endDrawer: _buildEndDrawer(context),
      body: Column(
        children: <Widget>[
          if (_searchVisible && searcher != null)
            SearchBarView(
              searcher: searcher,
              onClose: _toggleSearch,
              initialQuery: widget.initialHighlight.trim(),
            ),
          Expanded(child: _buildViewer()),
          _buildBottomBar(context),
        ],
      ),
    );
  }

  Widget _buildViewer() {
    final Widget viewer = PdfViewer.file(
      widget.filePath,
      controller: _controller,
      params: _params,
      initialPageNumber: widget.initialPage < 1 ? 1 : widget.initialPage,
    );
    if (!AppStore.instance.invertPages) {
      return viewer;
    }
    // Approximate night reading mode by inverting the rendered page colours.
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        -1, 0, 0, 0, 255, //
        0, -1, 0, 0, 255, //
        0, 0, -1, 0, 255, //
        0, 0, 0, 1, 0, //
      ]),
      child: viewer,
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 4,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          child: Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: '上一页',
                onPressed: _pageNumber > 1 ? () => _goToPage(_pageNumber - 1) : null,
              ),
              Expanded(
                child: Center(
                  child: TextButton(
                    onPressed: _pageCount > 0 ? _showJumpDialog : null,
                    child: Text(
                      _pageCount > 0 ? '$_pageNumber / $_pageCount' : '$_pageNumber',
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: '下一页',
                onPressed: _pageCount > 0 && _pageNumber < _pageCount
                    ? () => _goToPage(_pageNumber + 1)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.zoom_out),
                tooltip: '缩小',
                onPressed: () => _controller.zoomDown(),
              ),
              IconButton(
                icon: const Icon(Icons.zoom_in),
                tooltip: '放大',
                onPressed: () => _controller.zoomUp(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEndDrawer(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: <Widget>[
              const TabBar(
                tabs: <Widget>[
                  Tab(text: '目录'),
                  Tab(text: '缩略图'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: <Widget>[
                    OutlineView(
                      subject: _subject,
                      document: _document,
                      pageOffset: _pageOffset,
                      webOffset: _webOffset,
                      onOpenPage: (int pageNumber) {
                        _scaffoldKey.currentState?.closeEndDrawer();
                        unawaited(_goToPage(pageNumber));
                      },
                      onOffsetChanged: _changeOffset,
                      onWebOffsetChanged: _changeWebOffset,
                    ),
                    ThumbnailsView(
                      document: _document,
                      currentPage: _pageNumber,
                      onOpenPage: (int pageNumber) {
                        _scaffoldKey.currentState?.closeEndDrawer();
                        unawaited(_goToPage(pageNumber));
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
