import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'utils.dart';

/// Copies opened PDFs into the app's private `library/` directory.
///
/// On Android the system file picker hands back a `content://` URI (no real
/// path) whose access grant is not persistent, so the bytes are imported once
/// and the local copy is used afterwards. That keeps the recent list working
/// across restarts.
class PdfImporter {
  static Future<Directory> _libraryDir() async {
    final Directory root = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${root.path}/library');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Imports a file returned by the platform picker.
  static Future<String> importPlatformFile(PlatformFile file) async {
    final String? localPath = file.path;
    final String name = safeFileName(file.name);
    if (localPath != null) {
      return importLocalFile(localPath, name);
    }
    final Directory dir = await _libraryDir();
    final File target = File('${dir.path}/$name');
    final IOSink sink = target.openWrite();
    try {
      await for (final List<int> chunk in file.readAsByteStream()) {
        sink.add(chunk);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    return target.path;
  }

  /// Imports a file that already lives on the local disk.
  static Future<String> importLocalFile(String sourcePath, String fileName) async {
    final Directory dir = await _libraryDir();
    final File target = File('${dir.path}/${safeFileName(fileName)}');
    final File source = File(sourcePath);
    if (source.absolute.path == target.absolute.path) {
      return target.path;
    }
    await source.copy(target.path);
    return target.path;
  }

  /// Deletes a local copy created by one of the import methods.
  ///
  /// Only files that live inside the app's own library directory are removed.
  static Future<void> deleteLocalCopy(String path) async {
    try {
      final Directory dir = await _libraryDir();
      final File file = File(path);
      if (!isInside(dir.path, file.parent.path)) return;
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // The shelf entry is already gone; a failed delete is not actionable.
    }
  }
}
