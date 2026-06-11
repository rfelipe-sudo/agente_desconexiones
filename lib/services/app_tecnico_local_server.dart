import 'dart:io';

/// Sirve el bundle `www` en localhost para que Ionic cargue bien en WebView.
class AppTecnicoLocalServer {
  HttpServer? _server;

  int? get port => _server?.port;

  Future<String> start(Directory wwwDir) async {
    await stop();
    final dir = wwwDir.absolute;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    _server!.listen((request) async {
      try {
        var path = request.uri.path;
        if (path.startsWith('/')) path = path.substring(1);
        if (path.isEmpty) path = 'index.html';

        if (path.contains('..')) {
          request.response.statusCode = HttpStatus.forbidden;
          await request.response.close();
          return;
        }

        final file = File('${dir.path}/$path');
        if (!file.existsSync()) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        request.response.headers.set(
          'Content-Type',
          _contentType(path),
        );
        request.response.headers.set('Cache-Control', 'no-cache');
        await request.response.addStream(file.openRead());
        await request.response.close();
      } catch (_) {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {}
      }
    });

    return 'http://127.0.0.1:${_server!.port}/';
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  static String _contentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.html')) return 'text/html; charset=utf-8';
    if (lower.endsWith('.js')) return 'application/javascript; charset=utf-8';
    if (lower.endsWith('.css')) return 'text/css; charset=utf-8';
    if (lower.endsWith('.json')) return 'application/json; charset=utf-8';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.woff2')) return 'font/woff2';
    if (lower.endsWith('.woff')) return 'font/woff';
    if (lower.endsWith('.ttf')) return 'font/ttf';
    if (lower.endsWith('.map')) return 'application/json';
    return 'application/octet-stream';
  }
}
