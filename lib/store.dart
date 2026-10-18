import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'pdf_files.dart';
import 'toc.dart';

/// App wide settings plus the user's shelf of books.
///
/// Settings live in [SharedPreferences]; the shelf is written to
/// `history.json` in the app documents directory.
class AppStore extends ChangeNotifier {
  AppStore._();

  static final AppStore instance = AppStore._();

  static const String _shelfFileName = 'history.json';
  static const String _themeKey = 'themeMode';
  static const String _invertKey = 'invertPages';

  final List<ShelfBook> _shelf = <ShelfBook>[];
  ThemeMode _themeMode = ThemeMode.system;
  bool _invertPages = false;
  SharedPreferences? _prefs;
  File? _shelfFile;

  /// Books added by the user, most recently opened first.
  List<ShelfBook> get shelf => List<ShelfBook>.unmodifiable(_shelf);

  ThemeMode get themeMode => _themeMode;

  /// Whether PDF pages are colour-inverted for night reading.
  bool get invertPages => _invertPages;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final String? storedMode = _prefs!.getString(_themeKey);
    _themeMode = ThemeMode.values.firstWhere(
      (ThemeMode mode) => mode.name == storedMode,
      orElse: () => ThemeMode.system,
    );
    _invertPages = _prefs!.getBool(_invertKey) ?? false;

    final Directory dir = await getApplicationDocumentsDirectory();
    _shelfFile = File('${dir.path}/$_shelfFileName');
    if (await _shelfFile!.exists()) {
      try {
        final Map<String, dynamic> json =
            jsonDecode(await _shelfFile!.readAsString()) as Map<String, dynamic>;
        final List<dynamic> items = json['items'] as List<dynamic>? ?? <dynamic>[];
        _shelf
          ..clear()
          ..addAll(
            items.map((dynamic e) => ShelfBook.fromJson(e as Map<String, dynamic>)),
          );
      } catch (_) {
        // Corrupted shelf file: start from an empty shelf.
      }
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await _prefs?.setString(_themeKey, mode.name);
    notifyListeners();
  }

  Future<void> setInvertPages(bool value) async {
    if (_invertPages == value) return;
    _invertPages = value;
    await _prefs?.setBool(_invertKey, value);
    notifyListeners();
  }

  Future<void> toggleInvertPages() => setInvertPages(!_invertPages);

  /// Adds [path] to the shelf, or refreshes it if it is already there.
  ///
  /// [subject] is only changed when explicitly provided, so re-opening a book
  /// keeps the subject the user picked when adding it.
  Future<void> addBook({
    required String path,
    required String title,
    String? subject,
    int totalPages = 0,
  }) async {
    final int index = _shelf.indexWhere((ShelfBook b) => b.path == path);
    final ShelfBook? previous = index >= 0 ? _shelf[index] : null;
    final ShelfBook entry = ShelfBook(
      path: path,
      title: title,
      subject: subject ?? previous?.subject ?? kSubjectNone,
      pageOffset: previous?.pageOffset ?? 0,
      page: previous?.page ?? 1,
      totalPages: totalPages > 0 ? totalPages : (previous?.totalPages ?? 0),
      openedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _shelf.removeWhere((ShelfBook b) => b.path == path);
    _shelf.insert(0, entry);
    notifyListeners();
    await _save();
  }

  /// Persists the page offset used by the curated table of contents.
  Future<void> setPageOffset(String path, int offset) async {
    final int index = _shelf.indexWhere((ShelfBook b) => b.path == path);
    if (index < 0) return;
    if (_shelf[index].pageOffset == offset) return;
    _shelf[index] = _shelf[index].copyWith(pageOffset: offset);
    notifyListeners();
    await _save();
  }

  /// Which subject [path] is filed under; either a 408os.cn book code or
  /// [kSubjectNone] when the PDF has no counterpart on the website.
  String subjectOf(String path) {
    final int index = _shelf.indexWhere((ShelfBook b) => b.path == path);
    return index < 0 ? kSubjectNone : _shelf[index].subject;
  }

  /// The shelf book currently bound to a 408os.cn book code, if any.
  ShelfBook? bookForCode(String code) {
    if (code.isEmpty) return null;
    for (final ShelfBook book in _shelf) {
      if (book.subject == code) return book;
    }
    return null;
  }

  /// Permanently binds [path] to a website book code.
  ///
  /// A code resolves to a single local file, so any other book previously bound
  /// to the same code is released first.
  Future<void> bindBook(String path, String code) async {
    final int index = _shelf.indexWhere((ShelfBook b) => b.path == path);
    if (index < 0 || code.isEmpty) return;
    bool changed = false;
    for (int i = 0; i < _shelf.length; i++) {
      if (i != index && _shelf[i].subject == code) {
        _shelf[i] = _shelf[i].copyWith(subject: kSubjectNone);
        changed = true;
      }
    }
    if (_shelf[index].subject != code) {
      _shelf[index] = _shelf[index].copyWith(subject: code);
      changed = true;
    }
    if (!changed) return;
    notifyListeners();
    await _save();
  }

  /// Page offset currently stored for [path].
  int pageOffsetOf(String path) {
    final int index = _shelf.indexWhere((ShelfBook b) => b.path == path);
    return index < 0 ? 0 : _shelf[index].pageOffset;
  }

  /// Records the page the user reached in [path].
  Future<void> updatePage(String path, int page, int totalPages) async {
    final int index = _shelf.indexWhere((ShelfBook b) => b.path == path);
    if (index < 0) return;
    final ShelfBook entry = _shelf[index];
    if (entry.page == page && (totalPages <= 0 || entry.totalPages == totalPages)) {
      return;
    }
    _shelf[index] = entry.copyWith(
      page: page,
      totalPages: totalPages > 0 ? totalPages : entry.totalPages,
    );
    notifyListeners();
    await _save();
  }

  /// Removes a book from the shelf and deletes its local copy.
  Future<void> removeBook(String path) async {
    final int before = _shelf.length;
    _shelf.removeWhere((ShelfBook b) => b.path == path);
    if (_shelf.length == before) return;
    notifyListeners();
    await _save();
    await PdfImporter.deleteLocalCopy(path);
  }

  Future<void> _save() async {
    final File? file = _shelfFile;
    if (file == null) return;
    try {
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          'version': 1,
          'items': _shelf.map((ShelfBook b) => b.toJson()).toList(),
        }),
      );
    } catch (_) {
      // Best effort persistence; nothing actionable if the disk is unavailable.
    }
  }
}
