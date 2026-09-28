import 'dart:io';

import 'package:shelf/shelf.dart';

import 'http_util.dart';

/// Fixed one-minute window per client address. Enough to slow down password
/// guessing on a single small server; not shared across instances.
Middleware rateLimit({
  required int perMinute,
  required bool Function(Request) applies,
  DateTime Function() clock = DateTime.now,
}) {
  final windows = <String, ({int minute, int count})>{};

  return (inner) => (request) {
    if (!applies(request) || request.method == 'OPTIONS') return inner(request);

    final minute = clock().millisecondsSinceEpoch ~/ 60000;
    final key = _clientKey(request);
    final w = windows[key];
    final count = (w != null && w.minute == minute) ? w.count + 1 : 1;
    windows[key] = (minute: minute, count: count);

    if (windows.length > 10000) {
      windows.removeWhere((_, v) => v.minute != minute);
    }

    if (count > perMinute) {
      final retry = 60 - (clock().millisecondsSinceEpoch ~/ 1000) % 60;
      return errorResponse(
        429,
        'too_many_requests',
        'Too many attempts. Wait a minute and try again.',
        headers: {'retry-after': '$retry'},
      );
    }
    return inner(request);
  };
}

String _clientKey(Request request) {
  final info = request.context['shelf.io.connection_info'];
  if (info is HttpConnectionInfo) return info.remoteAddress.address;
  return 'unknown';
}
