import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

const defaultPort = 8080;

String _proxyUrl = '';

Future<void> startServer({int port = defaultPort, String proxyUrl = ''}) async {
  _proxyUrl = proxyUrl;
  
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(_router.call);

  final server = await shelf_io.serve(handler, 'localhost', port);
  print(
    '🐸 FroggyDocs server running at http://${server.address.host}:${server.port}',
  );
  print('📖 Open http://${server.address.host}:${server.port} in your browser');
}

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

String get _packageDir {
  final exePath = Platform.resolvedExecutable;
  final exeDir = File(exePath).parent.path;
  return p.dirname(exeDir);
}

String get webDir => p.join(_packageDir, 'frontend', 'web');
String get deployDir => p.join(_packageDir, 'frontend', 'deploy', 'web');

String get userWebDir => p.join(Directory.current.path, 'frontend', 'web');

Router get _router {
  final router = Router();

  router.get('/froggy_docs.json', (Request request) async {
    var file = File(p.join(userWebDir, 'froggy_docs.json'));
    if (file.existsSync()) {
      return Response.ok(
        file.openRead(),
        headers: {'Content-Type': 'application/json'},
      );
    }
    file = File(p.join(webDir, 'froggy_docs.json'));
    if (file.existsSync()) {
      return Response.ok(
        file.openRead(),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.notFound('{"error": "Not found"}');
  });

  router.get('/', (Request request) async {
    final indexFile = File(p.join(webDir, 'index.html'));
    if (indexFile.existsSync()) {
      return Response.ok(
        indexFile.openRead(),
        headers: {'Content-Type': 'text/html'},
      );
    }
    return Response.notFound('index.html not found');
  });

  router.post('/api/simple', (Request request) async {
    final body = await request.readAsString();
    return Response.ok(
      jsonEncode({
        'status': 'success',
        'received': body.isNotEmpty ? jsonDecode(body) : {},
      }),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.post('/api/me', (Request request) async {
    return Response.ok(
      jsonEncode({
        'message': 'Logged in',
        'user': {'email': 'test@example.com', 'id': 1},
      }),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.put('/api/inline-json', (Request request) async {
    return Response.ok(
      jsonEncode({
        'status': 'updated',
        'timestamp': DateTime.now().toIso8601String(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.post('/api/upload', (Request request) async {
    final contentType = request.headers['content-type'] ?? '';
    if (contentType.contains('multipart/form-data')) {
      return Response.ok(
        jsonEncode({
          'status': 'success',
          'message': 'File upload received (multipart/form-data)',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final body = await request.readAsString();
    return Response.ok(
      jsonEncode({
        'status': 'success',
        'received': body.isNotEmpty ? jsonDecode(body) : {},
      }),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.get(
    '/api/simple',
    (Request request) => Response.ok(
      '{"message": "GET works"}',
      headers: {'Content-Type': 'application/json'},
    ),
  );
  router.get(
    '/api/me',
    (Request request) => Response.ok(
      '{"message": "GET /api/me"}',
      headers: {'Content-Type': 'application/json'},
    ),
  );
  router.get(
    '/api/inline-json',
    (Request request) => Response.ok(
      '{"message": "GET /api/inline-json"}',
      headers: {'Content-Type': 'application/json'},
    ),
  );
  router.delete(
    '/api/simple',
    (Request request) => Response.ok(
      '{"message": "Deleted"}',
      headers: {'Content-Type': 'application/json'},
    ),
  );

  router.all('/api/<path.*>', (Request request, String path) async {
    if (_proxyUrl.isEmpty) {
      return Response.notFound('{"error": "Proxy not configured. Use --proxy http://localhost:3000"');
    }

    try {
      final targetUrl = '$_proxyUrl/api/$path';
      final method = request.method;
      final contentType = request.headers['content-type'] ?? '';

      final client = http.Client();
      http.Request req;

      if (method == 'GET' || method == 'HEAD') {
        req = http.Request(method, Uri.parse(targetUrl));
      } else if (contentType.contains('multipart/form-data')) {
        // Read as bytes to preserve binary file data.
        final chunks = <int>[];
        await for (final chunk in request.read()) {
          chunks.addAll(chunk);
        }
        req = http.Request(method, Uri.parse(targetUrl));
        req.bodyBytes = Uint8List.fromList(chunks);
      } else {
        final body = await request.readAsString();
        req = http.Request(method, Uri.parse(targetUrl));
        if (body.isNotEmpty) {
          req.body = body;
        }
      }

      request.headers.forEach((key, value) {
        if (key.toLowerCase() != 'host') {
          req.headers[key] = value;
        }
      });

      if (contentType.contains('multipart/form-data')) {
        req.headers['content-type'] = contentType;
      }

      final streamedResponse = await client.send(req);
      final responseBody = await streamedResponse.stream.bytesToString();
      
      return Response(
        streamedResponse.statusCode,
        body: responseBody,
        headers: {
          'Content-Type': streamedResponse.headers['content-type'] ?? 'application/json',
          ..._corsHeaders,
        },
      );
    } catch (e) {
      return Response.internalServerError(
        body: '{"error": "Proxy error: $e"}',
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  router.get('/<path|[^/]+>', (Request request, String path) async {
    var file = File(p.join(deployDir, path));
    if (file.existsSync()) {
      return Response.ok(
        file.openRead(),
        headers: {'Content-Type': _getContentType(path)},
      );
    }
    file = File(p.join(webDir, path));
    if (file.existsSync()) {
      return Response.ok(
        file.openRead(),
        headers: {'Content-Type': _getContentType(path)},
      );
    }
    return Response.notFound('File not found: $path');
  });

  return router;
}

String _getContentType(String path) {
  final ext = p.extension(path).toLowerCase();
  return switch (ext) {
    '.html' => 'text/html',
    '.css' => 'text/css',
    '.js' => 'application/javascript',
    '.json' => 'application/json',
    '.svg' => 'image/svg+xml',
    '.ico' => 'image/x-icon',
    _ => 'application/octet-stream',
  };
}
