import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;

import 'components/file_field.dart';

class App extends StatefulComponent {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  Map<String, dynamic>? apiData;
  Timer? _timer;
  bool _isDark = false;
  String _searchQuery = '';
  String _authHeader = '';
  final Map<String, String> _responses = {};
  final Map<String, bool> _loading = {};
  final Map<String, Map<String, String>> _bodyValues = {};
  final Map<String, Map<String, dynamic>> _fileValues = {};
  final Map<String, Map<String, String>> _queryValues = {};
  final Map<String, Map<String, String>> _headerValues = {};
  final Map<String, bool> _expandedBody = {};
  final Map<String, bool> _expandedQuery = {};
  final Map<String, bool> _expandedHeaders = {};
  String? _toast;
  Timer? _toastTimer;
  // ignore: unused_field
  int _specVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadSpec();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _loadSpec());
    try {
      if (web.window.matchMedia('(prefers-color-scheme: dark)').matches) {
        _isDark = true;
        _applyTheme();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  void _applyTheme() {
    try {
      web.document.documentElement
          ?.setAttribute('data-theme', _isDark ? 'dark' : 'light');
    } catch (_) {}
  }

  Future<void> _loadSpec() async {
    try {
      final resp = await http.get(Uri.parse('/froggy_docs.json'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          final old = apiData;
          apiData = data;
          if (old != null && jsonEncode(old) != jsonEncode(data)) {
            _specVersion++;
            _toast = '🔄 Spec hot-reloaded!';
            _toastTimer?.cancel();
            _toastTimer = Timer(const Duration(seconds: 3), () {
              setState(() => _toast = null);
            });
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _executeRequest(
    String method,
    String path,
    bool hasAuth,
    Map<String, dynamic>? bodyProps,
    List<Map<String, dynamic>> queryParams,
    List<Map<String, dynamic>> headerParams,
    bool hasFiles,
  ) async {
    final key = '$method-$path';
    setState(() => _loading[key] = true);

    try {
      var uri = Uri.parse('${web.window.location.origin}$path');

      if (queryParams.isNotEmpty) {
        final savedQuery = _queryValues[key] ?? {};
        final params = <String, String>{};
        for (final qp in queryParams) {
          final name = qp['name'] as String;
          final val = savedQuery[name] ?? '';
          if (val.isNotEmpty) params[name] = val;
        }
        if (params.isNotEmpty) {
          uri = uri.replace(queryParameters: params);
        }
      }

      final headers = <String, String>{};
      if (!hasFiles) headers['Content-Type'] = 'application/json';
      if (_authHeader.isNotEmpty) headers['Authorization'] = _authHeader;
      for (final hp in headerParams) {
        final name = hp['name'] as String;
        final val = (_headerValues[key] ?? {})[name] ?? '';
        if (val.isNotEmpty) headers[name] = val;
      }

      http.Response resp;

      if (hasFiles) {
        final req = http.MultipartRequest(method.toUpperCase(), uri);
        req.headers.addAll(headers);
        final savedValues = _bodyValues[key] ?? {};
        final savedFiles = _fileValues[key] ?? {};

        for (final entry in (bodyProps ?? {}).entries) {
          final name = entry.key;
          final prop = entry.value as Map<String, dynamic>;
          if (prop['format'] == 'binary') {
            final fileData = savedFiles[name];
            if (fileData != null) {
              req.files.add(http.MultipartFile.fromBytes(
                name,
                fileData['bytes'] as List<int>,
                filename: fileData['name'] as String,
              ));
            }
          } else {
            final val = savedValues[name] ?? '';
            if (val.isNotEmpty) req.fields[name] = val;
          }
        }

        final streamed = await req.send();
        resp = await http.Response.fromStream(streamed);
      } else {
        final req = http.Request(method.toUpperCase(), uri);
        req.headers.addAll(headers);

        if (method.toUpperCase() != 'GET' && method.toUpperCase() != 'HEAD') {
          final savedValues = _bodyValues[key] ?? {};
          final bodyData = <String, dynamic>{};
          for (final entry in (bodyProps ?? {}).entries) {
            final val = savedValues[entry.key] ?? '';
            if (val.isNotEmpty) bodyData[entry.key] = val;
          }
          req.body = jsonEncode(bodyData);
        }

        final client = http.Client();
        try {
          final streamed = await client.send(req);
          resp = await http.Response.fromStream(streamed);
        } finally {
          client.close();
        }
      }

      String responseText;
      try {
        final json = jsonDecode(resp.body);
        responseText = const JsonEncoder.withIndent('  ').convert(json);
      } catch (_) {
        responseText = resp.body;
      }

      setState(() {
        _responses[key] =
            resp.statusCode >= 200 && resp.statusCode < 300
                ? responseText
                : 'Error ${resp.statusCode}: $responseText';
      });
    } catch (e) {
      setState(() => _responses[key] = 'Error: $e');
    } finally {
      setState(() => _loading[key] = false);
    }
  }

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'app-container',
      [
        _buildSidebar(),
        _buildMain(),
        if (_toast != null)
          div(classes: 'toast', [Component.text(_toast!)]),
      ],
    );
  }

  Map<String, List<Map<String, String>>> _getEndpointsByTag() {
    final byTag = <String, List<Map<String, String>>>{};
    final paths = (apiData?['paths'] as Map<String, dynamic>?) ?? {};
    for (final pathEntry in paths.entries) {
      final pathStr = pathEntry.key;
      for (final methodEntry
          in (pathEntry.value as Map<String, dynamic>).entries) {
        final method = methodEntry.key;
        final spec = methodEntry.value as Map<String, dynamic>;
        final tags =
            (spec['tags'] as List<dynamic>?)?.map((t) => t.toString()).toList()
            ?? ['Untagged'];
        for (final tag in tags) {
          byTag.putIfAbsent(tag, () => []).add({
            'path': pathStr,
            'method': method,
          });
        }
      }
    }
    return byTag;
  }

  Component _buildSidebar() {
    final byTag = _getEndpointsByTag();
    final navGroups = <Component>[];

    for (final entry in byTag.entries) {
      final tag = entry.key;
      final endpoints = entry.value;
      if (_searchQuery.isNotEmpty &&
          !tag.toLowerCase().contains(_searchQuery.toLowerCase()) &&
          !endpoints.any(
            (ep) => ep['path']!
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()),
          )) {
        continue;
      }
      navGroups.add(div(
        classes: 'tag-group',
        [
          div(classes: 'tag-header', [Component.text('▶ $tag')]),
          div(
            classes: 'tag-endpoints',
            endpoints
                .map<Component>(
                  (ep) => a(
                    href: '#${ep['method']!.toUpperCase()}-${ep['path']!}',
                    classes: 'nav-item',
                    [
                      span(
                        classes: 'method-tag ${ep['method']!.toUpperCase()}',
                        [Component.text(ep['method']!.toUpperCase())],
                      ),
                      Component.text(' ${ep['path']!}'),
                    ],
                  ),
                )
                .toList(),
          ),
        ],
      ));
    }

    return div(
      classes: 'sidebar',
      [
        div(classes: 'sidebar-header', [
          h2([Component.text('🐸 FroggyDocs')]),
        ]),
        div(classes: 'search-container', [
          input<String>(
            type: InputType.search,
            classes: 'search-box',
            attributes: const {'placeholder': 'Search tags or endpoints...'},
            onInput: (val) => setState(() => _searchQuery = val),
          ),
        ]),
        nav(classes: 'nav-list', navGroups),
      ],
    );
  }

  Component _buildMain() {
    final paths = (apiData?['paths'] as Map<String, dynamic>?) ?? {};
    final cards = <Component>[];

    for (final pathEntry in paths.entries) {
      for (final methodEntry
          in (pathEntry.value as Map<String, dynamic>).entries) {
        cards.add(_buildEndpointCard(
          pathEntry.key,
          methodEntry.key,
          methodEntry.value as Map<String, dynamic>,
        ));
      }
    }

    return div(
      classes: 'main-content',
      [
        div(classes: 'header', [
          h1([
            Component.text(
              apiData?['info']?['title']?.toString() ?? 'API Documentation',
            ),
          ]),
          button(
            classes: 'theme-toggle',
            onClick: () => setState(() {
              _isDark = !_isDark;
              _applyTheme();
            }),
            [Component.text(_isDark ? '☀️' : '🌙')],
          ),
        ]),
        div(classes: 'settings-section', [
          span([Component.text('Authorization: ')]),
          input<String>(
            type: InputType.text,
            classes: 'auth-input',
            attributes: const {'placeholder': 'Bearer token'},
            onInput: (val) => setState(() => _authHeader = val),
          ),
        ]),
        div(id: 'apiList', cards),
      ],
    );
  }

  Component _buildEndpointCard(
    String path,
    String method,
    Map<String, dynamic> spec,
  ) {
    final key = '$method-$path';
    final hasAuth = spec['security'] != null;
    final isExpanded = _expandedBody[key] ?? false;
    final isLoading = _loading[key] ?? false;
    final response = _responses[key];

    final jsonProps = spec['requestBody']?['content']?['application/json']
        ?['schema']?['properties'] as Map<String, dynamic>?;
    final multipartProps = spec['requestBody']?['content']
        ?['multipart/form-data']?['schema']?['properties']
        as Map<String, dynamic>?;
    final bodyProps = jsonProps ?? multipartProps;
    final hasFiles = multipartProps != null;

    final allParams = (spec['parameters'] as List<dynamic>?) ?? [];
    final queryParams = allParams
        .whereType<Map<String, dynamic>>()
        .where((param) => param['in'] == 'query')
        .toList();
    final headerParams = allParams
        .whereType<Map<String, dynamic>>()
        .where((param) => param['in'] == 'header')
        .toList();
    final responseSchemas = spec['responses'] as Map<String, dynamic>?;

    final children = <Component>[
      div(classes: 'endpoint-header', [
        span(
          classes: 'method-tag ${method.toUpperCase()}',
          [Component.text(method.toUpperCase())],
        ),
        span(classes: 'path-text', [Component.text(path)]),
        if (hasAuth) span(classes: 'auth-badge', [Component.text('🔒 Auth')]),
      ]),
      p(classes: 'api-description', [
        Component.text(spec['summary']?.toString() ?? 'No description'),
      ]),
    ];

    if (bodyProps != null && bodyProps.isNotEmpty) {
      children.add(button(
        classes: 'try-it-out-btn${isExpanded ? '' : ' secondary'}',
        onClick: () => setState(() => _expandedBody[key] = !isExpanded),
        [Component.text(isExpanded ? 'Hide Request Body' : 'Show Request Body')],
      ));
      if (isExpanded) {
        children.add(_buildFormSection(key, bodyProps, hasFiles));
      }
    }

    if (queryParams.isNotEmpty) {
      children.add(_buildQuerySection(key, queryParams));
    }
    if (headerParams.isNotEmpty) {
      children.add(_buildHeadersSection(key, headerParams));
    }
    if (responseSchemas != null) {
      children.add(_buildResponseSchemas(responseSchemas));
    }

    children.add(button(
      classes: 'try-it-out-btn',
      disabled: isLoading,
      onClick: isLoading
          ? null
          : () => _executeRequest(
                method,
                path,
                hasAuth,
                bodyProps,
                queryParams,
                headerParams,
                hasFiles,
              ),
      [Component.text(isLoading ? 'Loading...' : 'Try It Out')],
    ));

    if (response != null) {
      children.add(div(classes: 'response-section', [
        h4([Component.text('Response:')]),
        pre(classes: 'response-body', [Component.text(response)]),
      ]));
    }

    return div(
      id: '${method.toUpperCase()}-$path',
      classes: 'api-section',
      children,
    );
  }

  Component _buildFormSection(
    String key,
    Map<String, dynamic> props,
    bool hasFiles,
  ) {
    final fields = props.entries.map<Component>((entry) {
      final name = entry.key;
      final value = entry.value as Map<String, dynamic>;
      final isFile = value['format'] == 'binary';
      final description = value['description']?.toString() ?? '';
      final fieldType = value['type']?.toString() ?? 'string';
      final savedValue = (_bodyValues[key] ?? {})[name] ?? '';

      return FileField(
        endpointKey: key,
        fieldName: name,
        description: description,
        isFile: isFile,
        fieldType: fieldType,
        savedValue: savedValue,
        onTextChanged: (val) => setState(() {
          _bodyValues[key] ??= {};
          _bodyValues[key]![name] = val;
        }),
        onFileSelected: (bytes, fileName) => setState(() {
          _fileValues[key] ??= {};
          _fileValues[key]![name] = {'bytes': bytes, 'name': fileName};
        }),
      );
    }).toList();

    return div(classes: 'request-body-form', [
      h3(classes: 'section-title', [
        Component.text(hasFiles ? 'Multipart Form Data' : 'Request Body'),
      ]),
      ...fields,
    ]);
  }

  Component _buildQuerySection(
    String key,
    List<Map<String, dynamic>> params,
  ) {
    final isExpanded = _expandedQuery[key] ?? false;
    final children = <Component>[
      button(
        classes: 'collapsible-btn',
        onClick: () => setState(() => _expandedQuery[key] = !isExpanded),
        [Component.text(isExpanded ? '▲ Query Params' : '▼ Query Params')],
      ),
    ];

    if (isExpanded) {
      for (final qp in params) {
        final name = qp['name'] as String;
        final desc = qp['description']?.toString() ?? '';
        final schema = qp['schema'] as Map<String, dynamic>? ?? {};
        final type = schema['type']?.toString() ?? 'string';
        final defaultVal = schema['default']?.toString() ?? '';
        final savedVal = (_queryValues[key] ?? {})[name] ?? '';

        children.add(div(classes: 'form-field', [
          label([Component.text('$name ($type)')]),
          if (desc.isNotEmpty) span(classes: 'field-desc', [Component.text(desc)]),
          input<String>(
            type: InputType.text,
            classes: 'form-input',
            value: savedVal.isEmpty ? defaultVal : savedVal,
            attributes: {'placeholder': defaultVal},
            onInput: (val) => setState(() {
              _queryValues[key] ??= {};
              _queryValues[key]![name] = val;
            }),
          ),
        ]));
      }
    }

    return div(classes: 'query-section', children);
  }

  Component _buildHeadersSection(
    String key,
    List<Map<String, dynamic>> params,
  ) {
    final isExpanded = _expandedHeaders[key] ?? false;
    final children = <Component>[
      button(
        classes: 'collapsible-btn',
        onClick: () => setState(() => _expandedHeaders[key] = !isExpanded),
        [Component.text(isExpanded ? '▲ Headers' : '▼ Headers')],
      ),
    ];

    if (isExpanded) {
      for (final hp in params) {
        final name = hp['name'] as String;
        final desc = hp['description']?.toString() ?? '';
        final schema = hp['schema'] as Map<String, dynamic>? ?? {};
        final type = schema['type']?.toString() ?? 'string';
        final savedVal = (_headerValues[key] ?? {})[name] ?? '';

        children.add(div(classes: 'form-field', [
          label([Component.text('$name ($type)')]),
          if (desc.isNotEmpty) span(classes: 'field-desc', [Component.text(desc)]),
          input<String>(
            type: InputType.text,
            classes: 'form-input',
            value: savedVal,
            onInput: (val) => setState(() {
              _headerValues[key] ??= {};
              _headerValues[key]![name] = val;
            }),
          ),
        ]));
      }
    }

    return div(classes: 'headers-section', children);
  }

  Component _buildResponseSchemas(Map<String, dynamic> responses) {
    final items = responses.entries.map<Component>((entry) {
      final code = entry.key;
      final resp = entry.value as Map<String, dynamic>;
      final desc = resp['description']?.toString() ?? '';
      final content =
          resp['content']?['application/json'] as Map<String, dynamic>?;
      final schema = content?['schema'] as Map<String, dynamic>?;
      final example = content?['example'];

      return div(classes: 'response-schema', [
        div(classes: 'response-code', [Component.text('$code - $desc')]),
        if (schema != null)
          div(classes: 'schema-type', [
            Component.text('Type: ${schema['type'] ?? 'object'}'),
          ]),
        if (example != null)
          pre(classes: 'schema-example', [
            Component.text(const JsonEncoder.withIndent('  ').convert(example)),
          ]),
      ]);
    }).toList();

    return div(classes: 'response-schemas', [
      h3(classes: 'section-title', [Component.text('Responses')]),
      ...items,
    ]);
  }
}
