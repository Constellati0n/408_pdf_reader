import 'toc.dart';

/// A book on the user's shelf, persisted in `history.json`.
///
/// Every book here is a copy the user added themselves; the app ships no
/// bundled documents.
class ShelfBook {
  ShelfBook({
    required this.path,
    required this.title,
    this.subject = kSubjectNone,
    this.pageOffset = 0,
    this.webOffset = 0,
    this.page = 1,
    this.totalPages = 0,
    this.openedAt = 0,
  });

  /// Absolute path of the local copy inside the app's private library.
  final String path;

  final String title;

  /// Textbook this PDF is filed under: a 408os.cn book code such as `26wdds`,
  /// or [kSubjectNone] when the PDF has no counterpart on the website. The
  /// code also selects the curated table of contents, see [TocRepository].
  final String subject;

  /// Added to the table of contents page numbers when jumping, to compensate
  /// for copies whose pagination differs from the reference printing.
  final int pageOffset;

  /// Added to the page number 408os.cn sends when jumping into the book.
  ///
  /// The website quotes the textbook's *printed* page, while the table of
  /// contents above uses PDF page numbers; for a copy with extra front matter
  /// the two need different corrections, so this is kept separate.
  final int webOffset;

  /// Last read page (1-based).
  final int page;

  /// Total page count, 0 until the document has been opened.
  final int totalPages;

  /// Milliseconds since epoch of the last time the book was opened.
  final int openedAt;

  ShelfBook copyWith({
    String? subject,
    int? page,
    int? totalPages,
    int? openedAt,
    int? pageOffset,
    int? webOffset,
  }) {
    return ShelfBook(
      path: path,
      title: title,
      subject: subject ?? this.subject,
      pageOffset: pageOffset ?? this.pageOffset,
      webOffset: webOffset ?? this.webOffset,
      page: page ?? this.page,
      totalPages: totalPages ?? this.totalPages,
      openedAt: openedAt ?? this.openedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'path': path,
    'title': title,
    'subject': subject,
    'pageOffset': pageOffset,
    'webOffset': webOffset,
    'page': page,
    'totalPages': totalPages,
    'openedAt': openedAt,
  };

  factory ShelfBook.fromJson(Map<String, dynamic> json) {
    return ShelfBook(
      path: json['path'] as String? ?? '',
      title: json['title'] as String? ?? 'PDF',
      subject: json['subject'] as String? ?? kSubjectNone,
      pageOffset: (json['pageOffset'] as num?)?.toInt() ?? 0,
      webOffset: (json['webOffset'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
      openedAt: (json['openedAt'] as num?)?.toInt() ?? 0,
    );
  }
}
