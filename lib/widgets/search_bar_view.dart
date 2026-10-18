import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Full text search bar driving a [PdfTextSearcher].
class SearchBarView extends StatefulWidget {
  const SearchBarView({
    super.key,
    required this.searcher,
    required this.onClose,
    this.initialQuery = '',
  });

  final PdfTextSearcher searcher;
  final VoidCallback onClose;

  /// Text to show in the field when the bar opens, used to surface the snippet
  /// a `zt408os://` deep link asked the reader to highlight.
  final String initialQuery;

  @override
  State<SearchBarView> createState() => _SearchBarViewState();
}

class _SearchBarViewState extends State<SearchBarView> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.searcher.addListener(_onSearcherChanged);
    if (widget.initialQuery.isNotEmpty) {
      _controller.text = widget.initialQuery;
      _query = widget.initialQuery;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.searcher.removeListener(_onSearcherChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onSearcherChanged() {
    if (mounted) setState(() {});
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      final String query = _query.trim();
      if (query.isEmpty) {
        widget.searcher.resetTextSearch();
        return;
      }
      widget.searcher.startTextSearch(RegExp(RegExp.escape(query), caseSensitive: false));
    });
  }

  String get _status {
    if (_query.trim().isEmpty) return '';
    if (widget.searcher.isSearching) return '搜索中…';
    final int total = widget.searcher.matches.length;
    if (total == 0) return '无匹配';
    final int current = (widget.searcher.currentIndex ?? 0) + 1;
    return '$current/$total';
  }

  @override
  Widget build(BuildContext context) {
    final bool hasMatches = widget.searcher.matches.isNotEmpty;
    return Material(
      elevation: 2,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: '搜索全文',
                    isDense: true,
                    border: InputBorder.none,
                  ),
                  onChanged: _onQueryChanged,
                  onSubmitted: (_) {
                    if (hasMatches) widget.searcher.goToNextMatch();
                  },
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                tooltip: '上一个',
                onPressed: hasMatches ? () => widget.searcher.goToPrevMatch() : null,
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                tooltip: '下一个',
                onPressed: hasMatches ? () => widget.searcher.goToNextMatch() : null,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: '关闭搜索',
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
