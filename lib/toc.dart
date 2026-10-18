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

/// A subject the app has a curated table of contents for.
class TocSubject {
  const TocSubject({required this.id, required this.label});

  final String id;
  final String label;
}

/// Subject id used when the PDF should fall back to its own embedded outline.
const String kSubjectNone = 'none';

const List<TocSubject> kSubjects = <TocSubject>[
  TocSubject(id: 'ds', label: '数据结构'),
  TocSubject(id: 'coa', label: '计算机组成原理'),
  TocSubject(id: 'os', label: '操作系统'),
  TocSubject(id: 'network', label: '计算机网络'),
  TocSubject(id: kSubjectNone, label: '其他（用 PDF 自带目录）'),
];

String subjectLabel(String id) {
  for (final TocSubject subject in kSubjects) {
    if (subject.id == id) return subject.label;
  }
  return kSubjectNone;
}

/// Loads the curated tables of contents shipped in `assets/toc/`.
///
/// Each entry keeps the page numbers of the reference printing; the reader
/// applies the user's page offset on top when jumping.
class TocRepository {
  static final Map<String, List<TocEntry>> _cache = <String, List<TocEntry>>{};

  static Future<List<TocEntry>> load(String subjectId) async {
    if (subjectId == kSubjectNone) return const <TocEntry>[];
    final List<TocEntry>? cached = _cache[subjectId];
    if (cached != null) return cached;
    final String raw = await rootBundle.loadString('assets/toc/$subjectId.json');
    final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
    final List<dynamic> items = json['items'] as List<dynamic>? ?? <dynamic>[];
    final List<TocEntry> entries =
        items.map((dynamic e) => _parse(e as Map<String, dynamic>)).toList();
    _cache[subjectId] = entries;
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
