import 'package:flutter/services.dart';

/// A `zt408os://` jump request produced by the 408os.cn website.
///
/// The website builds either `zt408os://<code>?page=&highlight=` or the
/// templated `zt408os://?book=<code>&page=&highlight=`; the Android side
/// normalises both into this shape.
class DeepLink {
  const DeepLink({
    required this.bookCode,
    required this.page,
    required this.highlight,
  });

  /// Website book code, e.g. `26wdds`. Empty when the link carried none.
  final String bookCode;

  /// 1-based page of the reference printing the website wants to land on.
  final int page;

  /// Snippet to look up once the page is open. May be empty.
  final String highlight;

  static DeepLink? fromArguments(Object? arguments) {
    if (arguments is! Map) return null;
    final String code = (arguments['book'] as String? ?? '').trim();
    if (code.isEmpty) return null;
    return DeepLink(
      bookCode: code,
      page: (arguments['page'] as num?)?.toInt() ?? 1,
      highlight: (arguments['highlight'] as String? ?? '').trim(),
    );
  }
}

/// Single bridge to the Android activity for inbound intents: "open with"
/// files and `zt408os://` deep links.
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

  /// Deep link that launched the activity, if any.
  static Future<DeepLink?> initialDeepLink() async {
    try {
      final Object? raw = await _channel.invokeMethod<Object>('getInitialDeepLink');
      return DeepLink.fromArguments(raw);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Routes intents arriving while the app is already running.
  static void setHandlers({
    void Function(String path)? onFile,
    void Function(DeepLink link)? onDeepLink,
  }) {
    _channel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'onFileOpened':
          final String? path = call.arguments as String?;
          if (path != null) onFile?.call(path);
        case 'onDeepLink':
          final DeepLink? link = DeepLink.fromArguments(call.arguments);
          if (link != null) onDeepLink?.call(link);
      }
      return null;
    });
  }
}
