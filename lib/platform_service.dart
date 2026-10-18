import 'package:flutter/services.dart';

/// Single bridge to the Android activity for inbound "open with" files.
class PlatformService {
  static const MethodChannel _channel =
      MethodChannel('cn.d408os.zt_pdf_reader/intent');

  /// Path of the file that launched the activity, if any.
  ///
  /// The Android side renames any `content://` PDF it received into the app
  /// cache first, so this is always a local path.
  static Future<String?> initialFile() async {
    try {
      return await _channel.invokeMethod<String>('getInitialFile');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Registers [onFile] for files arriving while the app is already running.
  static void setFileHandler(void Function(String path) onFile) {
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onFileOpened') {
        final String? path = call.arguments as String?;
        if (path != null) {
          onFile(path);
        }
      }
      return null;
    });
  }
}
