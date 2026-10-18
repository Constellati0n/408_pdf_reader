import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../toc.dart';

/// Document table of contents.
///
/// When [subject] has a curated table of contents shipped with the app, that
/// one is used and its page numbers are corrected with [pageOffset]. Otherwise
/// the PDF's own embedded outline is shown.
///
/// Books filed under a 408os.cn book code also get a second stepper: the page
/// number the website sends is the textbook's *printed* page, so it needs its
/// own correction ([webOffset]).
class OutlineView extends StatefulWidget {
  const OutlineView({
    super.key,
    required this.subject,
    required this.document,
    required this.pageOffset,
    required this.webOffset,
    required this.onOpenPage,
    required this.onOffsetChanged,
    required this.onWebOffsetChanged,
  });

  final String subject;

  /// Needed only for the embedded-outline fallback.
  final PdfDocument? document;

  final int pageOffset;

  /// Correction applied to page numbers coming from 408os.cn.
  final int webOffset;

  final void Function(int pageNumber) onOpenPage;
  final Future<void> Function(int offset) onOffsetChanged;
  final Future<void> Function(int offset) onWebOffsetChanged;

  @override
  State<OutlineView> createState() => _OutlineViewState();
}

class _OutlineViewState extends State<OutlineView> {
  Future<List<TocEntry>>? _future;

  bool get _usesBuiltIn => TocRepository.hasCurated(widget.subject);

  /// Only books the website knows about can be jumped into from a web page.
  bool get _showsWebOffset => TocRepository.bookFor(widget.subject) != null;

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(OutlineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subject != widget.subject ||
        !identical(oldWidget.document, widget.document)) {
      _maybeLoad();
    }
  }

  void _maybeLoad() {
    if (_usesBuiltIn) {
      _future = TocRepository.load(widget.subject);
      return;
    }
    final PdfDocument? document = widget.document;
    _future = document?.loadOutline().then(_fromOutlineNodes);
  }

  static List<TocEntry> _fromOutlineNodes(List<PdfOutlineNode> nodes) =>
      nodes.map(_fromOutlineNode).toList();

  static TocEntry _fromOutlineNode(PdfOutlineNode node) => TocEntry(
        title: node.title,
        page: node.dest?.pageNumber ?? 0,
        children: node.children.map(_fromOutlineNode).toList(),
      );

  @override
  Widget build(BuildContext context) {
    final Future<List<TocEntry>>? future = _future;
    if (future == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: <Widget>[
        Expanded(
          child: FutureBuilder<List<TocEntry>>(
            future: future,
            builder: (
              BuildContext context,
              AsyncSnapshot<List<TocEntry>> snapshot,
            ) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _message(context, '目录读取失败');
              }
              final List<TocEntry> entries = snapshot.data ?? const <TocEntry>[];
              if (entries.isEmpty) {
                return _message(context, '该文档没有目录');
              }
              return ListView(children: _buildEntries(context, entries, 0));
            },
          ),
        ),
        if (_usesBuiltIn)
          _offsetBar(
            context,
            title: '目录页码偏移',
            hint: '目录页码 + 偏移 = 实际跳转页',
            offset: widget.pageOffset,
            onChanged: widget.onOffsetChanged,
          ),
        if (_showsWebOffset)
          _offsetBar(
            context,
            title: '网页跳转偏移',
            hint: '网站页码 + 偏移 = 实际跳转页',
            offset: widget.webOffset,
            onChanged: widget.onWebOffsetChanged,
          ),
      ],
    );
  }

  Widget _message(BuildContext context, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }

  List<Widget> _buildEntries(
    BuildContext context,
    List<TocEntry> entries,
    int depth,
  ) {
    final List<Widget> widgets = <Widget>[];
    for (final TocEntry entry in entries) {
      final int target = entry.page > 0
          ? entry.page + (_usesBuiltIn ? widget.pageOffset : 0)
          : 0;
      widgets.add(
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: 12 + depth * 14.0, right: 8),
          title: Text(
            entry.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          trailing: entry.page > 0
              ? Text('${entry.page}', style: Theme.of(context).textTheme.labelSmall)
              : null,
          onTap: target > 0 ? () => widget.onOpenPage(target) : null,
        ),
      );
      if (entry.children.isNotEmpty) {
        widgets.addAll(_buildEntries(context, entry.children, depth + 1));
      }
    }
    return widgets;
  }

  /// Stepper used to compensate for copies whose pagination differs from the
  /// reference printing the curated table of contents was built from.
  Widget _offsetBar(
    BuildContext context, {
    required String title,
    required String hint,
    required int offset,
    required Future<void> Function(int offset) onChanged,
  }) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '$title\n$hint',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: '偏移 -1',
              onPressed: () => onChanged(offset - 1),
            ),
            Tooltip(
              message: '重置为 0',
              child: InkWell(
                onTap: () => onChanged(0),
                child: SizedBox(
                  width: 46,
                  child: Text(
                    offset > 0 ? '+$offset' : '$offset',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: '偏移 +1',
              onPressed: () => onChanged(offset + 1),
            ),
          ],
        ),
      ),
    );
  }
}
