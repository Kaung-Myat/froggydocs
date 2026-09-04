import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

const defaultPort = 8080;
// Allows several files in one multipart request while retaining a bounded body.
const maxUploadBytes = 50 * 1024 * 1024;
const maxProxyResponseBytes = 10 * 1024 * 1024;
const proxyTimeout = Duration(seconds: 30);

String _proxyUrl = '';
String _docsBasePath = '/';
String? _specificationPath;
String? _resolvedPackageRoot;

Future<HttpServer> startServer({
  int port = defaultPort,
  String proxyUrl = '',
  String basePath = '/',
  String? specificationPath,
}) async {
  _proxyUrl = proxyUrl;
  _docsBasePath = _normalizeBasePath(basePath);
  _specificationPath = specificationPath == null
      ? null
      : p.absolute(specificationPath);
  final packageUri = await Isolate.resolvePackageUri(
    Uri.parse('package:froggy_docs/froggy_docs.dart'),
  );
  if (packageUri != null && packageUri.scheme == 'file') {
    _resolvedPackageRoot = p.dirname(p.dirname(packageUri.toFilePath()));
  }

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(_router.call);

  final server = await shelf_io.serve(handler, 'localhost', port);
  final docsUrl =
      'http://${server.address.host}:${server.port}${_docsBasePath == '/' ? '/' : _docsBasePath}';
  print('🐸 FroggyDocs server running at $docsUrl');
  print('📖 Open $docsUrl in your browser');
  return server;
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

String get userWebDir => p.join(Directory.current.path, 'frontend', 'web');

Iterable<String> get _assetRoots sync* {
  final configuredRoot = Platform.environment['FROGGY_DOCS_WEB_DIR'];
  if (configuredRoot != null && configuredRoot.isNotEmpty) {
    yield configuredRoot;
  }

  yield userWebDir;
  yield p.join(Directory.current.path, 'frontend', 'deploy', 'web');
  if (_resolvedPackageRoot != null) {
    yield p.join(_resolvedPackageRoot!, 'frontend', 'web');
    yield p.join(_resolvedPackageRoot!, 'frontend', 'deploy', 'web');
  }

  final executableDir = File(Platform.resolvedExecutable).parent.path;
  yield p.join(executableDir, 'frontend', 'web');
  yield p.join(executableDir, 'frontend', 'deploy', 'web');
  yield p.join(_packageDir, 'frontend', 'web');
  yield p.join(_packageDir, 'frontend', 'deploy', 'web');
}

File? _findAsset(String relativePath) {
  final normalized = p.posix.normalize(relativePath.replaceAll('\\', '/'));
  if (normalized == '..' || normalized.startsWith('../')) return null;
  for (final root in _assetRoots) {
    final file = File(p.join(root, normalized));
    if (file.existsSync()) return file;
  }
  return null;
}

Router get _router {
  final router = Router();

  if (_docsBasePath == '/') {
    router.get('/', (Request request) => _serveAsset('index.html'));
    router.get('/froggy_docs.json', (Request request) => _serveSpecification());
  } else {
    final withoutTrailingSlash = _docsBasePath.substring(
      0,
      _docsBasePath.length - 1,
    );
    router.get(
      '/',
      (Request request) => Response.movedPermanently(_docsBasePath),
    );
    router.get(
      withoutTrailingSlash,
      (Request request) => Response.movedPermanently(_docsBasePath),
    );
    router.get(_docsBasePath, (Request request) => _serveAsset('index.html'));
    router.get(
      '${_docsBasePath}froggy_docs.json',
      (Request request) => _serveSpecification(),
    );
  }

  router.get('/uploads/<path|.*>', (Request request, String path) async {
    if (_proxyUrl.isEmpty) {
      return Response.notFound(
        jsonEncode({'error': 'Media proxy is not configured'}),
        headers: {'Content-Type': 'application/json', ..._corsHeaders},
      );
    }

    final client = http.Client();
    try {
      final proxyBase = _proxyUrl.endsWith('/')
          ? _proxyUrl.substring(0, _proxyUrl.length - 1)
          : _proxyUrl;
      var targetUri = Uri.parse('$proxyBase/uploads/$path');
      if (request.requestedUri.hasQuery) {
        targetUri = targetUri.replace(query: request.requestedUri.query);
      }
      final streamedResponse = await client
          .send(http.Request('GET', targetUri))
          .timeout(proxyTimeout);
      final responseBody = await _readLimitedResponseBytes(
        streamedResponse.stream,
      ).timeout(proxyTimeout);

      return Response(
        streamedResponse.statusCode,
        body: responseBody,
        headers: {
          'Content-Type':
              streamedResponse.headers['content-type'] ??
              'application/octet-stream',
          'Cache-Control':
              streamedResponse.headers['cache-control'] ??
              'private, max-age=60',
          ..._corsHeaders,
        },
      );
    } on TimeoutException {
      return Response(
        HttpStatus.gatewayTimeout,
        body: jsonEncode({'error': 'Media proxy request timed out'}),
        headers: {'Content-Type': 'application/json', ..._corsHeaders},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Media proxy error: $e'}),
        headers: {'Content-Type': 'application/json', ..._corsHeaders},
      );
    } finally {
      client.close();
    }
  });

  router.all('/api/<path|.*>', (Request request, String path) async {
    return _proxyRequest(request, '/api/$path');
  });

  if (_docsBasePath == '/') {
    router.get('/<path|[^/]+>', (Request request, String path) {
      final asset = _findAsset(path);
      if (asset != null) return _serveFile(asset, path);
      return _proxyRequest(request, '/$path');
    });
  } else {
    router.get(
      '$_docsBasePath<path|.*>',
      (Request request, String path) => _serveAsset(path),
    );
  }

  router.all('/<path|.*>', (Request request, String path) {
    return _proxyRequest(request, '/$path');
  });

  return router;
}

Response _serveAsset(String path) {
  final file = _findAsset(path);
  if (file == null) return Response.notFound('File not found: $path');
  return _serveFile(file, path);
}

Response _serveFile(File file, String path) {
  return Response.ok(
    file.openRead(),
    headers: {'Content-Type': _getContentType(path)},
  );
}

Response _serveSpecification() {
  final configuredPath = _specificationPath;
  if (configuredPath != null) {
    final file = File(configuredPath);
    if (!file.existsSync()) {
      return Response.notFound('Specification not found: $configuredPath');
    }
    return Response.ok(
      file.openRead(),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }
  return _serveAsset('froggy_docs.json');
}

Future<Response> _proxyRequest(Request request, String targetPath) async {
  if (request.method == 'OPTIONS') {
    return Response.ok('', headers: _corsHeaders);
  }
  if (_proxyUrl.isEmpty) {
    return Response.notFound(
      jsonEncode({
        'error': 'Proxy not configured. Use --proxy http://localhost:3000',
      }),
      headers: {'Content-Type': 'application/json', ..._corsHeaders},
    );
  }

  final client = http.Client();
  try {
    final proxyBase = _proxyUrl.endsWith('/')
        ? _proxyUrl.substring(0, _proxyUrl.length - 1)
        : _proxyUrl;
    var targetUri = Uri.parse('$proxyBase$targetPath');
    if (request.requestedUri.hasQuery) {
      targetUri = targetUri.replace(query: request.requestedUri.query);
    }

    final upstreamRequest = http.Request(request.method, targetUri);
    if (request.method != 'GET' && request.method != 'HEAD') {
      final bodyBytes = await _readLimitedBody(request).timeout(proxyTimeout);
      if (bodyBytes.isNotEmpty) upstreamRequest.bodyBytes = bodyBytes;
    }
    request.headers.forEach((key, value) {
      const excludedHeaders = {
        'host',
        'content-length',
        'transfer-encoding',
        'connection',
      };
      if (!excludedHeaders.contains(key.toLowerCase())) {
        upstreamRequest.headers[key] = value;
      }
    });

    final upstreamResponse = await client
        .send(upstreamRequest)
        .timeout(proxyTimeout);
    final responseBody = await _readLimitedResponseBytes(
      upstreamResponse.stream,
    ).timeout(proxyTimeout);
    final responseHeaders = <String, String>{
      'Content-Type':
          upstreamResponse.headers['content-type'] ?? 'application/json',
      ..._corsHeaders,
    };
    for (final name in ['cache-control', 'content-disposition', 'location']) {
      final value = upstreamResponse.headers[name];
      if (value != null) responseHeaders[name] = value;
    }
    return Response(
      upstreamResponse.statusCode,
      body: responseBody,
      headers: responseHeaders,
    );
  } on _PayloadTooLargeException {
    return _payloadTooLarge();
  } on TimeoutException {
    return Response(
      HttpStatus.gatewayTimeout,
      body: jsonEncode({'error': 'Proxy request timed out'}),
      headers: {'Content-Type': 'application/json', ..._corsHeaders},
    );
  } catch (error) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Proxy error: $error'}),
      headers: {'Content-Type': 'application/json', ..._corsHeaders},
    );
  } finally {
    client.close();
  }
}

String _normalizeBasePath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == '/') return '/';
  return '/${trimmed.replaceAll(RegExp(r'^/+|/+$'), '')}/';
}

class _PayloadTooLargeException implements Exception {}

Future<Uint8List> _readLimitedBody(Request request) async {
  final declaredLength = request.contentLength;
  if (declaredLength != null && declaredLength > maxUploadBytes) {
    throw _PayloadTooLargeException();
  }

  final bytes = BytesBuilder(copy: false);
  var receivedBytes = 0;
  await for (final chunk in request.read()) {
    receivedBytes += chunk.length;
    if (receivedBytes > maxUploadBytes) throw _PayloadTooLargeException();
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

Response _payloadTooLarge() => Response(
  HttpStatus.requestEntityTooLarge,
  body: jsonEncode({
    'error':
        'Request body exceeds the ${maxUploadBytes ~/ (1024 * 1024)} MB limit',
  }),
  headers: {'Content-Type': 'application/json', ..._corsHeaders},
);

Future<Uint8List> _readLimitedResponseBytes(Stream<List<int>> stream) async {
  final bytes = BytesBuilder(copy: false);
  var receivedBytes = 0;
  await for (final chunk in stream) {
    receivedBytes += chunk.length;
    if (receivedBytes > maxProxyResponseBytes) {
      throw StateError(
        'Proxy response exceeds the '
        '${maxProxyResponseBytes ~/ (1024 * 1024)} MB limit',
      );
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
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
