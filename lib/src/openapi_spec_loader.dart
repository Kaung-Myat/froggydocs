import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

const maxOpenApiBytes = 10 * 1024 * 1024;
const openApiRequestTimeout = Duration(seconds: 20);

class OpenApiSpecLoader {
  OpenApiSpecLoader({
    this.basePath = '/',
    this.defaultEnvironment = '',
    this.configuredServers = const [],
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String basePath;
  final String defaultEnvironment;
  final List<Map<String, dynamic>> configuredServers;
  final http.Client _client;

  Future<Map<String, dynamic>> loadFile(String sourcePath) async {
    final file = File(p.absolute(sourcePath));
    if (!file.existsSync()) {
      throw FileSystemException(
        'OpenAPI specification does not exist',
        file.path,
      );
    }
    final length = await file.length();
    if (length > maxOpenApiBytes) {
      throw FormatException(
        'OpenAPI specification exceeds the ${maxOpenApiBytes ~/ (1024 * 1024)} MB limit',
        file.path,
      );
    }
    final bytes = await file.readAsBytes();
    return parse(bytes, source: file.path);
  }

  Future<Map<String, dynamic>> loadUrl(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw FormatException(
        '--spec-url only supports http:// and https:// URLs',
        uri.toString(),
      );
    }
    if (uri.userInfo.isNotEmpty) {
      throw FormatException(
        'Credentials are not allowed in --spec-url; use --spec-header-env',
        uri.toString(),
      );
    }

    final request = http.Request('GET', uri)
      ..followRedirects = true
      ..maxRedirects = 5
      ..headers.addAll(headers)
      ..headers.putIfAbsent(
        'Accept',
        () => 'application/json, application/yaml, text/yaml',
      );
    final response = await _client.send(request).timeout(openApiRequestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>();
      throw HttpException(
        'Unable to download OpenAPI specification: HTTP ${response.statusCode}',
        uri: uri,
      );
    }

    final bytes = await _readLimited(response.stream);
    return parse(bytes, source: uri.toString());
  }

  Map<String, dynamic> parse(List<int> bytes, {required String source}) {
    if (bytes.isEmpty) {
      throw FormatException('OpenAPI specification is empty', source);
    }
    if (bytes.length > maxOpenApiBytes) {
      throw FormatException(
        'OpenAPI specification exceeds the ${maxOpenApiBytes ~/ (1024 * 1024)} MB limit',
        source,
      );
    }

    final text = utf8.decode(bytes, allowMalformed: false);
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      try {
        decoded = loadYaml(text);
      } catch (error) {
        throw FormatException(
          'Unable to parse OpenAPI JSON or YAML: $error',
          source,
        );
      }
    }

    final plain = _toPlainValue(decoded);
    if (plain is! Map<String, dynamic>) {
      throw FormatException('OpenAPI root must be an object', source);
    }
    validate(plain, source: source);
    return _prepareForFroggyDocs(plain);
  }

  void validate(Map<String, dynamic> specification, {required String source}) {
    if (specification.containsKey('swagger')) {
      throw FormatException(
        'Swagger 2.0 is not supported yet. Convert this document to OpenAPI 3.0 or 3.1.',
        source,
      );
    }

    final version = specification['openapi'];
    if (version is! String ||
        !RegExp(r'^3\.(0|1)\.\d+([.-].*)?$').hasMatch(version)) {
      throw FormatException(
        'Unsupported or missing openapi version. Expected OpenAPI 3.0.x or 3.1.x.',
        source,
      );
    }

    final info = specification['info'];
    if (info is! Map ||
        info['title'] is! String ||
        (info['title'] as String).trim().isEmpty) {
      throw FormatException('info.title must be a non-empty string', source);
    }
    if (info['version'] is! String ||
        (info['version'] as String).trim().isEmpty) {
      throw FormatException('info.version must be a non-empty string', source);
    }

    final paths = specification['paths'];
    if (paths is! Map) {
      throw FormatException('paths must be an object', source);
    }
    const operations = {
      'get',
      'post',
      'put',
      'patch',
      'delete',
      'options',
      'head',
      'trace',
    };
    for (final entry in paths.entries) {
      final pathName = entry.key.toString();
      if (!pathName.startsWith('/')) {
        throw FormatException('paths.$pathName must start with /', source);
      }
      if (entry.value is! Map) {
        throw FormatException('paths.$pathName must be an object', source);
      }
      final pathItem = entry.value as Map;
      for (final operation in pathItem.entries) {
        final method = operation.key.toString().toLowerCase();
        if (operations.contains(method) && operation.value is! Map) {
          throw FormatException(
            'paths.$pathName.$method must be an object',
            source,
          );
        }
      }
    }

    _validateReferences(specification, specification, source, r'$');
  }

  Future<bool> write(
    Map<String, dynamic> specification,
    String outputPath,
  ) async {
    final file = File(p.absolute(outputPath));
    final encoded =
        '${const JsonEncoder.withIndent('  ').convert(specification)}\n';
    if (file.existsSync() && await file.readAsString() == encoded) return false;

    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.$pid.tmp');
    try {
      await temporary.writeAsString(encoded, flush: true);
      if (Platform.isWindows && file.existsSync()) await file.delete();
      await temporary.rename(file.path);
    } finally {
      if (temporary.existsSync()) await temporary.delete();
    }
    return true;
  }

  Map<String, dynamic> _prepareForFroggyDocs(Map<String, dynamic> input) {
    final specification = _resolveReferences(input, input, <String>{});
    _normalizeOperations(specification);
    if (configuredServers.isNotEmpty) {
      specification['servers'] = configuredServers;
    }
    final existingExtension = specification['x-froggy-docs'];
    final extension = existingExtension is Map
        ? Map<String, dynamic>.from(existingExtension)
        : <String, dynamic>{};
    extension['basePath'] = basePath;
    if (defaultEnvironment.isNotEmpty) {
      extension['defaultEnvironment'] = defaultEnvironment;
    }
    specification['x-froggy-docs'] = extension;
    return specification;
  }

  void _normalizeOperations(Map<String, dynamic> specification) {
    const methods = {
      'get',
      'post',
      'put',
      'patch',
      'delete',
      'options',
      'head',
      'trace',
    };
    final paths = specification['paths'];
    if (paths is! Map<String, dynamic>) return;
    final globalSecurity = specification['security'];

    for (final pathEntry in paths.entries.toList()) {
      final pathItem = pathEntry.value;
      if (pathItem is! Map) continue;
      final pathParameters = pathItem['parameters'] is List
          ? List<dynamic>.from(pathItem['parameters'] as List)
          : <dynamic>[];
      final normalizedPath = <String, dynamic>{};

      for (final entry in pathItem.entries) {
        final method = entry.key.toString().toLowerCase();
        if (!methods.contains(method) || entry.value is! Map) continue;
        final operation = Map<String, dynamic>.from(entry.value as Map);
        final operationParameters = operation['parameters'] is List
            ? List<dynamic>.from(operation['parameters'] as List)
            : <dynamic>[];
        if (pathParameters.isNotEmpty) {
          operation['parameters'] = _mergeParameters(
            pathParameters,
            operationParameters,
          );
        }
        if (!operation.containsKey('security') && globalSecurity != null) {
          operation['security'] = globalSecurity;
        }
        _normalizeJsonContent(operation['requestBody']);
        final responses = operation['responses'];
        if (responses is Map) {
          for (final response in responses.values) {
            _normalizeJsonContent(response);
          }
        }
        normalizedPath[method] = operation;
      }
      paths[pathEntry.key] = normalizedPath;
    }
  }

  List<dynamic> _mergeParameters(
    List<dynamic> inherited,
    List<dynamic> operation,
  ) {
    final merged = <String, dynamic>{};
    for (final parameter in [...inherited, ...operation]) {
      if (parameter is! Map) continue;
      final name = parameter['name']?.toString() ?? '';
      final location = parameter['in']?.toString() ?? '';
      merged['$location\u0000$name'] = parameter;
    }
    return merged.values.toList();
  }

  void _normalizeJsonContent(dynamic container) {
    if (container is! Map || container['content'] is! Map) return;
    final content = container['content'] as Map;
    if (!content.containsKey('application/json')) {
      final compatible = content.entries.where((entry) {
        final type = entry.key.toString().toLowerCase();
        return type.endsWith('+json') || type.contains('/json');
      }).firstOrNull;
      if (compatible != null) content['application/json'] = compatible.value;
    }

    for (final mediaType in content.values.whereType<Map>()) {
      if (mediaType.containsKey('example') || mediaType['examples'] is! Map) {
        continue;
      }
      final examples = mediaType['examples'] as Map;
      if (examples.isEmpty) continue;
      final first = examples.values.first;
      if (first is Map && first.containsKey('value')) {
        mediaType['example'] = first['value'];
      }
    }
  }

  Map<String, dynamic> _resolveReferences(
    Map<String, dynamic> document,
    Map<String, dynamic> root,
    Set<String> stack,
  ) {
    dynamic resolve(dynamic value) {
      if (value is List) return value.map(resolve).toList();
      if (value is! Map) return value;

      final map = Map<String, dynamic>.from(value);
      final reference = map[r'$ref'];
      if (reference is String && reference.startsWith('#/')) {
        if (stack.contains(reference)) return map;
        final target = _resolvePointer(root, reference);
        if (target is Map) {
          final nextStack = {...stack, reference};
          final resolved = _resolveReferences(
            Map<String, dynamic>.from(target),
            root,
            nextStack,
          );
          map.remove(r'$ref');
          resolved.addAll(map.map((key, item) => MapEntry(key, resolve(item))));
          return resolved;
        }
      }
      return map.map((key, item) => MapEntry(key, resolve(item)));
    }

    return resolve(document) as Map<String, dynamic>;
  }

  void _validateReferences(
    dynamic value,
    Map<String, dynamic> root,
    String source,
    String location,
  ) {
    if (value is List) {
      for (var index = 0; index < value.length; index++) {
        _validateReferences(value[index], root, source, '$location[$index]');
      }
      return;
    }
    if (value is! Map) return;

    final reference = value[r'$ref'];
    if (reference is String) {
      if (!reference.startsWith('#/')) {
        throw FormatException(
          'External reference at $location is not supported yet: $reference',
          source,
        );
      }
      if (_resolvePointer(root, reference) == null) {
        throw FormatException(
          'Unresolved reference at $location: $reference',
          source,
        );
      }
    }
    for (final entry in value.entries) {
      _validateReferences(entry.value, root, source, '$location.${entry.key}');
    }
  }

  dynamic _resolvePointer(Map<String, dynamic> root, String reference) {
    dynamic current = root;
    for (final rawSegment in reference.substring(2).split('/')) {
      final segment = rawSegment.replaceAll('~1', '/').replaceAll('~0', '~');
      if (current is! Map || !current.containsKey(segment)) return null;
      current = current[segment];
    }
    return current;
  }

  Future<List<int>> _readLimited(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in stream.timeout(openApiRequestTimeout)) {
      received += chunk.length;
      if (received > maxOpenApiBytes) {
        throw const FormatException(
          'Remote OpenAPI specification exceeds the 10 MB limit',
        );
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  void close() => _client.close();
}

dynamic _toPlainValue(dynamic value) {
  if (value is YamlMap || value is Map) {
    return Map<String, dynamic>.fromEntries(
      (value as Map).entries.map(
        (entry) => MapEntry(entry.key.toString(), _toPlainValue(entry.value)),
      ),
    );
  }
  if (value is YamlList || value is List) {
    return (value as List).map(_toPlainValue).toList();
  }
  return value;
}
