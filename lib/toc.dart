import 'dart:convert';

import 'package:flutter/services.dart';

/// One chapter/section of a bundled table of contents.
class TocEntry {
  const TocEntry({
    required this.title,
    required this.page,
    this.children = const <TocEntry>[],
  });

  final String title;

  /// 1-based page number of the reference copy, before any user offset.
  final int page;

  final List<TocEntry> children;
}

/// A textbook from the 408os.cn catalogue the app can recognise.
class CatalogBook {
  const CatalogBook({
    required this.code,
    required this.name,
    required this.tocId,
  });

  /// Book code used by 408os.cn deep links (`zt408os://<code>?page=...`).
  final String code;

  /// Human readable name, e.g. `26 版王道数据结构`.
  final String name;

  /// Curated table of contents shipped with the app, empty when there is none
  /// (the PDF's own embedded outline is used instead).
  final String tocId;
}

/// A pickable entry in the "which textbook is this PDF?" dialog.
class TocSubject {
  const TocSubject({required this.id, required this.label});

  final String id;
  final String label;
}

/// Book code used when the PDF has no counterpart on the website.
const String kSubjectNone = 'none';

/// Subject ids stored by shelves created before book codes were introduced.
const Map<String, String> _legacyLabels = <String, String>{
  'ds': '数据结构',
  'coa': '计算机组成原理',
  'os': '操作系统',
  'network': '计算机网络',
};

/// Loads the textbook catalogue and the curated tables of contents shipped in
/// `assets/toc/`.
///
/// Each entry keeps the page numbers of the reference printing; the reader
/// applies the user's page offset on top when jumping.
class TocRepository {
  static const String _catalogAsset = 'assets/toc/catalog.json';

  static List<CatalogBook> _catalog = const <CatalogBook>[];
  static Map<String, CatalogBook> _byCode = const <String, CatalogBook>{};
  static final Map<String, List<TocEntry>> _cache = <String, List<TocEntry>>{};

  /// Books known from `catalog.json`, in catalogue order.
  static List<CatalogBook> get catalog => _catalog;

  /// Reads `catalog.json`; call once during start-up, before reading [choices].
  static Future<void> loadCatalog() async {
    if (_catalog.isNotEmpty) return;
    try {
      final String raw = await rootBundle.loadString(_catalogAsset);
      final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
      final List<dynamic> books = json['books'] as List<dynamic>? ?? <dynamic>[];
      _catalog = books
          .map((dynamic e) => e as Map<String, dynamic>)
          .map(
            (Map<String, dynamic> e) => CatalogBook(
              code: e['code'] as String? ?? '',
              name: e['name'] as String? ?? '',
              tocId: e['toc'] as String? ?? '',
            ),
          )
          .where((CatalogBook b) => b.code.isNotEmpty)
          .toList();
      _byCode = <String, CatalogBook>{
        for (final CatalogBook b in _catalog) b.code: b,
      };
    } catch (_) {
      // A missing or malformed catalogue only costs the handbook shortcuts.
      _catalog = const <CatalogBook>[];
      _byCode = const <String, CatalogBook>{};
    }
  }

  static CatalogBook? bookFor(String code) => _byCode[code];

  /// Curated table of contents id for [code], or null when none applies.
  static String? curatedIdFor(String code) {
    if (code.isEmpty || code == kSubjectNone) return null;
    final CatalogBook? book = _byCode[code];
    if (book != null) return book.tocId.isEmpty ? null : book.tocId;
    // Shelves created before book codes existed stored plain TOC ids.
    return _legacyLabels.containsKey(code) ? code : null;
  }

  /// Whether the app ships a curated table of contents for [code].
  static bool hasCurated(String code) => curatedIdFor(code) != null;

  /// Label shown on the shelf and in the book picker.
  static String labelFor(String code) {
    if (code == kSubjectNone) return '其他（用 PDF 自带目录）';
    final CatalogBook? book = _byCode[code];
    if (book != null) return book.name;
    return _legacyLabels[code] ?? code;
  }

  /// Every known textbook plus a "none" entry, for filing a local PDF.
  static List<TocSubject> get choices => <TocSubject>[
        ..._catalog.map(
          (CatalogBook b) => TocSubject(
            id: b.code,
            label: b.tocId.isEmpty ? '${b.name}（用 PDF 自带目录）' : b.name,
          ),
        ),
        const TocSubject(id: kSubjectNone, label: '其他（用 PDF 自带目录）'),
      ];

  static Future<List<TocEntry>> load(String code) async {
    final String? id = curatedIdFor(code);
    if (id == null) return const <TocEntry>[];
    final List<TocEntry>? cached = _cache[id];
    if (cached != null) return cached;
    final String raw = await rootBundle.loadString('assets/toc/$id.json');
    final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
    final List<dynamic> items = json['items'] as List<dynamic>? ?? <dynamic>[];
    final List<TocEntry> entries =
        items.map((dynamic e) => _parse(e as Map<String, dynamic>)).toList();
    _cache[id] = entries;
    return entries;
  }

  static TocEntry _parse(Map<String, dynamic> json) {
    return TocEntry(
      title: json['title'] as String? ?? '',
      page: (json['page'] as num?)?.toInt() ?? 0,
      children: (json['children'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => _parse(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
