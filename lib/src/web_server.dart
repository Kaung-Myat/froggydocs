import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:path/path.dart' as p;

const defaultPort = 8080;

Future<void> startServer({int port = defaultPort}) async {
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

const String webDir = 'frontend/web';
const String deployDir = 'frontend/deploy/web';

Router get _router {
  final router = Router();

  router.get('/froggy_docs.json', (Request request) async {
    final file = File(
      p.join(Directory.current.path, webDir, 'froggy_docs.json'),
    );
    if (await file.existsSync()) {
      return Response.ok(
        file.openRead(),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.notFound('{"error": "Not found"}');
  });

  router.get('/', (Request request) async {
    final indexFile = File(
      p.join(Directory.current.path, deployDir, 'index.html'),
    );
    if (await indexFile.existsSync()) {
      return Response.ok(
        indexFile.openRead(),
        headers: {'Content-Type': 'text/html'},
      );
    }
    return Response.notFound('index.html not found');
  });

  // ═════════════════════════════════════════════════════════════
  // Demo/Mock API Endpoints
  // These are included for testing "Try It Out" functionality
  // Remove these routes in production - your real API will handle requests
  // ═════════════════════════════════════════════════════════════
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

  // ═════════════════════════════════════════════════════════════
  // End of Demo/Mock API
  // In production: Remove lines 66-124 or connect to your real API
  // The "Try It Out" button will call your actual API endpoints
  // ═════════════════════════════════════════════════════════════

  router.get('/<path|[^/]+>', (Request request, String path) async {
    var file = File(p.join(Directory.current.path, deployDir, path));
    if (await file.existsSync()) {
      return Response.ok(
        file.openRead(),
        headers: {'Content-Type': _getContentType(path)},
      );
    }
    file = File(p.join(Directory.current.path, webDir, path));
    if (await file.existsSync()) {
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
