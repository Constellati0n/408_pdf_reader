/// Small path helpers shared across the app.
library;

/// Returns the trailing component of [path], handling both `/` and `\`.
String basename(String path) {
  final int slash = path.lastIndexOf('/');
  final int backslash = path.lastIndexOf(r'\');
  final int index = slash > backslash ? slash : backslash;
  return index < 0 ? path : path.substring(index + 1);
}

/// Human readable title for a PDF: file name without the extension.
String pdfTitle(String path) {
  final String name = basename(path);
  final int dot = name.lastIndexOf('.');
  if (dot <= 0) return name;
  return name.substring(0, dot);
}

/// Makes [name] safe to use as a single file name on disk.
String safeFileName(String name) {
  final String cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return cleaned.isEmpty ? 'document.pdf' : cleaned;
}

/// Whether [child] is [parent] itself or lies inside it.
///
/// Used as a guard before deleting anything, so a crafted path can never make
/// the app delete a file outside its own library directory.
bool isInside(String parent, String child) {
  final String p = _normalize(parent);
  final String c = _normalize(child);
  return c == p || c.startsWith('$p/');
}

String _normalize(String path) {
  final String unified = path.replaceAll(r'\', '/');
  final String trimmed = unified.endsWith('/')
      ? unified.substring(0, unified.length - 1)
      : unified;
  return trimmed.toLowerCase();
}
