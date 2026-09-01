import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:http/http.dart' as http;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;

import 'components/file_field.dart';

const requestTimeout = Duration(seconds: 30);

@JS('froggyTokenStorage.load')
external JSPromise<JSString?> _loadEncryptedAuthorizationToken();

@JS('froggyTokenStorage.save')
external JSPromise<JSAny?> _saveEncryptedAuthorizationToken(JSString token);

class App extends StatefulComponent {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  Map<String, dynamic>? apiData;
  Timer? _timer;
  bool _isDark = false;
  bool _isSidebarCollapsed = false;
  bool _showSettings = false;
  bool _isTokenVisible = false;
  bool _isSavingToken = false;
  bool _tokenSaveError = false;
  String _tokenSaveStatus = '';
  String _searchQuery = '';
  String _authHeader = '';
  final Map<String, String> _responses = {};
  final Map<String, List<String>> _responseMedia = {};
  final Map<String, bool> _loading = {};
  final Map<String, Map<String, String>> _bodyValues = {};
  final Map<String, Map<String, dynamic>> _fileValues = {};
  final Map<String, Map<String, String>> _queryValues = {};
  final Map<String, Map<String, String>> _headerValues = {};
  final Map<String, Map<String, String>> _pathValues = {};
  final Map<String, bool> _expandedBody = {};
  final Map<String, bool> _expandedQuery = {};
  final Map<String, bool> _expandedHeaders = {};
  final Map<String, bool> _expandedPath = {};
  String? _toast;
  Timer? _toastTimer;
  Timer? _copyFeedbackTimer;
  String? _copiedResponseKey;
  String? _previewMediaUrl;
  String? _rawSpec;
  bool _isLoadingSpec = false;
  bool _disposed = false;
  // ignore: unused_field
  int _specVersion = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSpec());
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isLoadingSpec) unawaited(_loadSpec());
    });
    _applyTheme();
    unawaited(_restoreAuthorizationToken());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _toastTimer?.cancel();
    _copyFeedbackTimer?.cancel();
    super.dispose();
  }

  void _applyTheme() {
    try {
      web.document.documentElement?.setAttribute('data-theme', _isDark ? 'dark' : 'light');
    } catch (_) {}
  }

  Future<void> _restoreAuthorizationToken() async {
    try {
      final saved = await _loadEncryptedAuthorizationToken().toDart;
      final token = saved?.toDart;
      if (!_disposed && token != null && token.isNotEmpty) {
        setState(() {
          _authHeader = token;
          _tokenSaveStatus = 'Saved token restored';
          _tokenSaveError = false;
        });
      }
    } catch (_) {
      if (!_disposed) {
        setState(() {
          _tokenSaveStatus = 'Unable to restore the saved token';
          _tokenSaveError = true;
        });
      }
    }
  }

  Future<void> _saveAuthorizationToken() async {
    final token = _authHeader.trim();
    setState(() => _isSavingToken = true);
    try {
      await _saveEncryptedAuthorizationToken(token.toJS).toDart;
      if (!_disposed) {
        setState(() {
          _authHeader = token;
          _tokenSaveStatus = token.isEmpty ? 'Saved token removed' : 'Token saved securely';
          _tokenSaveError = false;
        });
      }
    } catch (_) {
      if (!_disposed) {
        setState(() {
          _tokenSaveStatus = 'Encrypted storage is unavailable';
          _tokenSaveError = true;
        });
      }
    } finally {
      if (!_disposed) setState(() => _isSavingToken = false);
    }
  }

  Future<void> _copyResponse(String key, String response) async {
    try {
      await web.window.navigator.clipboard.writeText(response).toDart;
      if (_disposed) return;
      setState(() => _copiedResponseKey = key);
      _copyFeedbackTimer?.cancel();
      _copyFeedbackTimer = Timer(const Duration(milliseconds: 1400), () {
        if (!_disposed) setState(() => _copiedResponseKey = null);
      });
    } catch (_) {
      if (!_disposed) {
        setState(() => _toast = 'Unable to copy response');
        _toastTimer?.cancel();
        _toastTimer = Timer(const Duration(seconds: 3), () {
          if (!_disposed) setState(() => _toast = null);
        });
      }
    }
  }

  Future<void> _loadSpec() async {
    if (_isLoadingSpec || _disposed) return;
    _isLoadingSpec = true;
    final client = http.Client();
    try {
      final resp = await client.get(Uri.parse('/froggy_docs.json')).timeout(requestTimeout);
      if (resp.statusCode == 200 && resp.body != _rawSpec && !_disposed) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          final hadSpec = _rawSpec != null;
          _rawSpec = resp.body;
          apiData = data;
          if (hadSpec) {
            _specVersion++;
            _toast = 'API specification updated';
            _toastTimer?.cancel();
            _toastTimer = Timer(const Duration(seconds: 3), () {
              if (!_disposed) setState(() => _toast = null);
            });
          }
        });
      }
    } catch (_) {
      // Polling failures are intentionally retried on the next interval.
    } finally {
      client.close();
      _isLoadingSpec = false;
    }
  }

  Future<void> _executeRequest(
    String method,
    String path,
    bool hasAuth,
    Map<String, dynamic>? bodyProps,
    List<Map<String, dynamic>> queryParams,
    List<Map<String, dynamic>> headerParams,
    List<Map<String, dynamic>> pathParams,
    bool hasFiles,
  ) async {
    final key = '$method-$path';
    setState(() => _loading[key] = true);
    final client = http.Client();

    try {
      var resolvedPath = path;
      final savedPath = _pathValues[key] ?? {};
      for (final parameter in pathParams) {
        final name = parameter['name']?.toString() ?? '';
        final value = savedPath[name] ?? '';
        if (name.isNotEmpty && value.isNotEmpty) {
          resolvedPath = resolvedPath.replaceAll(
            '{$name}',
            Uri.encodeComponent(value),
          );
          resolvedPath = resolvedPath.replaceAll(
            ':$name',
            Uri.encodeComponent(value),
          );
        }
      }
      var uri = Uri.parse('${web.window.location.origin}$resolvedPath');

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
      final isGetOrHead = method.toUpperCase() == 'GET' || method.toUpperCase() == 'HEAD';
      if (!hasFiles && !isGetOrHead) headers['Content-Type'] = 'application/json';
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
          final isFile =
              prop['format'] == 'binary' || (prop['type'] == 'array' && prop['items']?['format'] == 'binary');
          if (isFile) {
            final fileData = savedFiles[name];
            final files = fileData is List ? fileData : (fileData == null ? const [] : [fileData]);
            for (final item in files) {
              final data = item as Map<String, dynamic>;
              req.files.add(
                http.MultipartFile.fromBytes(
                  name,
                  data['bytes'] as List<int>,
                  filename: data['name'] as String,
                ),
              );
            }
          } else {
            final val = savedValues[name] ?? '';
            if (val.isNotEmpty) req.fields[name] = val;
          }
        }

        final streamed = await client.send(req).timeout(requestTimeout);
        resp = await http.Response.fromStream(streamed).timeout(requestTimeout);
      } else if (isGetOrHead) {
        resp = await client.get(uri, headers: headers).timeout(requestTimeout);
      } else {
        final req = http.Request(method.toUpperCase(), uri);
        req.headers.addAll(headers);

        final savedValues = _bodyValues[key] ?? {};
        final bodyData = <String, dynamic>{};
        for (final entry in (bodyProps ?? {}).entries) {
          final val = savedValues[entry.key] ?? '';
          if (val.isNotEmpty) bodyData[entry.key] = val;
        }
        req.body = jsonEncode(bodyData);

        final streamed = await client.send(req).timeout(requestTimeout);
        resp = await http.Response.fromStream(streamed).timeout(requestTimeout);
      }

      String responseText;
      var mediaUrls = <String>[];
      try {
        final json = jsonDecode(resp.body);
        mediaUrls = _collectMediaUrls(json);
        responseText = const JsonEncoder.withIndent('  ').convert(json);
      } catch (_) {
        responseText = resp.body;
      }

      if (!_disposed) {
        setState(() {
          _responses[key] = resp.statusCode >= 200 && resp.statusCode < 300
              ? responseText
              : 'Error ${resp.statusCode}: $responseText';
          _responseMedia[key] = resp.statusCode >= 200 && resp.statusCode < 300 ? mediaUrls : [];
        });
      }
    } catch (e) {
      if (!_disposed) {
        setState(() {
          _responseMedia[key] = [];
          _responses[key] = 'Error: $e';
        });
      }
    } finally {
      client.close();
      if (!_disposed) setState(() => _loading[key] = false);
    }
  }

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'app-container${_isSidebarCollapsed ? ' sidebar-collapsed' : ''}',
      [
        _buildSidebar(),
        _buildMain(),
        if (_previewMediaUrl != null) _buildMediaPreview(),
        if (_toast != null) div(classes: 'toast is-visible', [Component.text(_toast!)]),
      ],
    );
  }

  List<String> _collectMediaUrls(dynamic value, [Set<String>? found]) {
    final urls = found ?? <String>{};
    if (value is String) {
      final uri = Uri.tryParse(value);
      final path = uri?.path.toLowerCase() ?? '';
      if ((value.startsWith('/') || uri?.hasScheme == true) && RegExp(r'\.(avif|gif|jpe?g|png|webp)$').hasMatch(path)) {
        urls.add(value);
      }
    } else if (value is List) {
      for (final item in value) {
        _collectMediaUrls(item, urls);
      }
    } else if (value is Map) {
      for (final item in value.values) {
        _collectMediaUrls(item, urls);
      }
    }
    return urls.toList();
  }

  Component _buildMediaPreview() {
    final url = _previewMediaUrl!;
    return dialog(open: true, classes: 'media-preview-dialog', [
      div(classes: 'media-preview-content', [
        div(classes: 'media-preview-header', [
          div([
            span(classes: 'eyebrow', [Component.text('Uploaded media')]),
            h2([Component.text('Media preview')]),
          ]),
          button(
            classes: 'media-preview-close',
            attributes: const {'aria-label': 'Close media preview', 'title': 'Close preview'},
            onClick: () => setState(() => _previewMediaUrl = null),
            [],
          ),
        ]),
        div(classes: 'media-preview-stage', [img(src: url, alt: 'Uploaded media preview')]),
        p(classes: 'media-preview-caption', [Component.text(url)]),
      ]),
    ]);
  }

  Map<String, List<Map<String, String>>> _getEndpointsByTag() {
    final byTag = <String, List<Map<String, String>>>{};
    final paths = (apiData?['paths'] as Map<String, dynamic>?) ?? {};
    for (final pathEntry in paths.entries) {
      final pathStr = pathEntry.key;
      for (final methodEntry in (pathEntry.value as Map<String, dynamic>).entries) {
        final method = methodEntry.key;
        final spec = methodEntry.value as Map<String, dynamic>;
        final tags = (spec['tags'] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? ['Untagged'];
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
            (ep) => ep['path']!.toLowerCase().contains(_searchQuery.toLowerCase()),
          )) {
        continue;
      }
      navGroups.add(
        div(
          classes: 'tag-group',
          [
            div(classes: 'tag-header', [
              span([Component.text(tag)]),
              span(classes: 'tag-count', [Component.text('${endpoints.length}')]),
            ]),
            div(
              classes: 'tag-endpoints',
              endpoints
                  .map<Component>(
                    (ep) => a(
                      href: '#${ep['method']!.toUpperCase()}-${ep['path']!}',
                      classes: 'nav-item',
                      onClick: () => setState(() => _showSettings = false),
                      [
                        span(
                          classes: 'method-tag ${ep['method']!.toUpperCase()}',
                          [Component.text(ep['method']!.toUpperCase())],
                        ),
                        span(classes: 'nav-path', [Component.text(ep['path']!)]),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      );
    }

    return div(
      classes: 'sidebar',
      [
        div(classes: 'sidebar-header', [
          div(classes: 'brand-copy', [
            strong([Component.text('FroggyDocs')]),
            span([Component.text('API workspace')]),
          ]),
          button(
            classes: 'sidebar-toggle',
            attributes: {
              'aria-label': _isSidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar',
              'title': _isSidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar',
            },
            onClick: () => setState(() {
              _isSidebarCollapsed = !_isSidebarCollapsed;
            }),
            [span(classes: 'sidebar-toggle-icon', [])],
          ),
        ]),
        div(classes: 'search-container', [
          input<String>(
            type: InputType.search,
            classes: 'search-box',
            attributes: const {'placeholder': 'Search endpoints'},
            onInput: (val) => setState(() => _searchQuery = val),
          ),
        ]),
        nav(classes: 'nav-list', navGroups),
        div(classes: 'sidebar-settings', [
          button(
            classes: 'settings-trigger${_showSettings ? ' is-active' : ''}',
            onClick: () => setState(() {
              if (_isSidebarCollapsed) _isSidebarCollapsed = false;
              _showSettings = true;
            }),
            [
              span(classes: 'settings-icon', []),
              span(classes: 'sidebar-control-label', [Component.text('Settings')]),
            ],
          ),
        ]),
      ],
    );
  }

  Component _buildMain() {
    final paths = (apiData?['paths'] as Map<String, dynamic>?) ?? {};
    final cards = <Component>[];

    for (final pathEntry in paths.entries) {
      for (final methodEntry in (pathEntry.value as Map<String, dynamic>).entries) {
        cards.add(
          _buildEndpointCard(
            pathEntry.key,
            methodEntry.key,
            methodEntry.value as Map<String, dynamic>,
          ),
        );
      }
    }

    return div(
      classes: 'main-content',
      _showSettings
          ? [_buildSettingsPage()]
          : [
              div(classes: 'header', [
                div(classes: 'title-group', [
                  span(classes: 'eyebrow', [Component.text('API reference')]),
                  h1([
                    Component.text(
                      apiData?['info']?['title']?.toString() ?? 'API Documentation',
                    ),
                  ]),
                  p([
                    Component.text(
                      apiData?['info']?['description']?.toString() ??
                          'Explore endpoints, inspect schemas, and send test requests.',
                    ),
                  ]),
                ]),
                div(classes: 'header-actions', [
                  span(classes: 'endpoint-count', [Component.text('${cards.length} endpoints')]),
                ]),
              ]),
              div(id: 'apiList', cards),
            ],
    );
  }

  Component _buildSettingsPage() {
    return section(classes: 'settings-page', [
      button(
        classes: 'back-button',
        attributes: const {
          'aria-label': 'Back to API documentation',
          'title': 'Back to API documentation',
        },
        onClick: () => setState(() => _showSettings = false),
        [span(classes: 'back-icon', [])],
      ),
      div(classes: 'settings-page-header', [
        span(classes: 'eyebrow', [Component.text('Workspace preferences')]),
        h1([Component.text('Settings')]),
        p([Component.text('Manage request authorization and the interface appearance.')]),
      ]),
      div(classes: 'settings-card', [
        div(classes: 'settings-card-copy', [
          h2([Component.text('Authorization')]),
          p([Component.text('Save an encrypted token in this browser and apply it to authenticated requests.')]),
        ]),
        div(classes: 'token-field', [
          label(htmlFor: 'authInput', [Component.text('Authorization token')]),
          div(classes: 'token-input-wrap', [
            input<String>(
              id: 'authInput',
              type: _isTokenVisible ? InputType.text : InputType.password,
              classes: 'auth-input',
              value: _authHeader,
              attributes: const {'placeholder': 'Bearer token or API key'},
              onInput: (val) => setState(() {
                _authHeader = val;
                _tokenSaveStatus = 'Unsaved changes';
                _tokenSaveError = false;
              }),
            ),
            button(
              classes: 'token-visibility-toggle${_isTokenVisible ? ' is-visible' : ''}',
              attributes: {
                'aria-label': _isTokenVisible ? 'Hide token' : 'Show token',
                'title': _isTokenVisible ? 'Hide token' : 'Show token',
              },
              onClick: () => setState(() => _isTokenVisible = !_isTokenVisible),
              [span(classes: 'visibility-icon', [])],
            ),
          ]),
          div(classes: 'token-save-row', [
            span(
              classes: 'token-save-status${_tokenSaveError ? ' is-error' : ''}',
              attributes: const {'role': 'status', 'aria-live': 'polite'},
              [Component.text(_tokenSaveStatus)],
            ),
            button(
              classes: 'save-token-button',
              disabled: _isSavingToken,
              onClick: _isSavingToken ? null : _saveAuthorizationToken,
              [Component.text(_isSavingToken ? 'Saving' : 'Save token')],
            ),
          ]),
        ]),
      ]),
      div(classes: 'settings-card', [
        div(classes: 'settings-card-copy', [
          h2([Component.text('Appearance')]),
          p([Component.text('Choose the color theme used by the API documentation.')]),
        ]),
        div(classes: 'theme-setting-row', [
          span([Component.text(_isDark ? 'Dark mode' : 'Light mode')]),
          button(
            classes: 'theme-icon-toggle',
            attributes: {
              'aria-label': _isDark ? 'Switch to light mode' : 'Switch to dark mode',
              'title': _isDark ? 'Switch to light mode' : 'Switch to dark mode',
            },
            onClick: () => setState(() {
              _isDark = !_isDark;
              _applyTheme();
            }),
            [span(classes: 'theme-icon', [])],
          ),
        ]),
      ]),
    ]);
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

    final jsonProps =
        spec['requestBody']?['content']?['application/json']?['schema']?['properties'] as Map<String, dynamic>?;
    final multipartProps =
        spec['requestBody']?['content']?['multipart/form-data']?['schema']?['properties'] as Map<String, dynamic>?;
    final bodyProps = jsonProps ?? multipartProps;
    final hasFiles = multipartProps != null;

    final allParams = (spec['parameters'] as List<dynamic>?) ?? [];
    final queryParams = allParams.whereType<Map<String, dynamic>>().where((param) => param['in'] == 'query').toList();
    final headerParams = allParams.whereType<Map<String, dynamic>>().where((param) => param['in'] == 'header').toList();
    final pathParams = allParams.whereType<Map<String, dynamic>>().where((param) => param['in'] == 'path').toList();
    final responseSchemas = spec['responses'] as Map<String, dynamic>?;

    final children = <Component>[
      div(classes: 'endpoint-header', [
        span(
          classes: 'method-tag ${method.toUpperCase()}',
          [Component.text(method.toUpperCase())],
        ),
        span(classes: 'path-text', [Component.text(path)]),
        if (hasAuth) span(classes: 'auth-badge', [Component.text('Authenticated')]),
      ]),
      p(classes: 'api-description', [
        Component.text(spec['summary']?.toString() ?? 'No description'),
      ]),
    ];

    if (bodyProps != null && bodyProps.isNotEmpty) {
      children.add(
        button(
          classes: 'try-it-out-btn${isExpanded ? '' : ' secondary'}',
          onClick: () => setState(() => _expandedBody[key] = !isExpanded),
          [Component.text(isExpanded ? 'Hide Request Body' : 'Show Request Body')],
        ),
      );
      if (isExpanded) {
        children.add(_buildFormSection(key, bodyProps, hasFiles));
      }
    }

    if (queryParams.isNotEmpty) {
      children.add(_buildQuerySection(key, queryParams));
    }
    if (pathParams.isNotEmpty) {
      children.add(_buildPathSection(key, pathParams));
    }
    if (headerParams.isNotEmpty) {
      children.add(_buildHeadersSection(key, headerParams));
    }
    if (responseSchemas != null) {
      children.add(_buildResponseSchemas(responseSchemas));
    }

    children.add(
      div(classes: 'endpoint-actions', [
        button(
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
                  pathParams,
                  hasFiles,
                ),
          [Component.text(isLoading ? 'Sending request' : 'Send request')],
        ),
      ]),
    );

    if (response != null) {
      final isCopied = _copiedResponseKey == key;
      final media = _responseMedia[key] ?? const <String>[];
      children.add(
        div(classes: 'response-section', [
          div(classes: 'response-heading', [
            h4([Component.text('Live response')]),
            button(
              classes: 'response-copy-btn${isCopied ? ' is-copied' : ''}',
              attributes: {
                'aria-label': isCopied ? 'Response copied' : 'Copy response',
                'title': isCopied ? 'Copied' : 'Copy response',
              },
              onClick: () => _copyResponse(key, response),
              [],
            ),
          ]),
          if (media.isNotEmpty)
            div(classes: 'response-media', [
              span(classes: 'response-media-label', [Component.text('Uploaded media')]),
              div(
                classes: 'response-media-grid',
                media.indexed
                    .map<Component>(
                      (entry) => button(
                        classes: 'response-media-item',
                        attributes: {'aria-label': 'Preview uploaded media ${entry.$1 + 1}'},
                        onClick: () => setState(() => _previewMediaUrl = entry.$2),
                        [img(src: entry.$2, alt: 'Uploaded media ${entry.$1 + 1}')],
                      ),
                    )
                    .toList(),
              ),
            ]),
          pre(classes: 'response-body', [Component.text(response)]),
        ]),
      );
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
      final isMultiple = value['type'] == 'array' && value['items']?['format'] == 'binary';
      final isFile = value['format'] == 'binary' || isMultiple;
      final description = value['description']?.toString() ?? '';
      final fieldType = value['type']?.toString() ?? 'string';
      final savedValue = (_bodyValues[key] ?? {})[name] ?? '';

      return FileField(
        endpointKey: key,
        fieldName: name,
        description: description,
        isFile: isFile,
        isMultiple: isMultiple,
        fieldType: fieldType,
        savedValue: savedValue,
        onTextChanged: (val) => setState(() {
          _bodyValues[key] ??= {};
          _bodyValues[key]![name] = val;
        }),
        onFilesSelected: (files) => setState(() {
          _fileValues[key] ??= {};
          _fileValues[key]![name] = files;
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
        classes: 'collapsible-btn${isExpanded ? ' is-expanded' : ''}',
        onClick: () => setState(() => _expandedQuery[key] = !isExpanded),
        [
          span([Component.text('Query parameters')]),
          span(classes: 'section-count', [Component.text('${params.length}')]),
        ],
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

        children.add(
          div(classes: 'form-field', [
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
          ]),
        );
      }
    }

    return div(classes: 'query-section', children);
  }

  Component _buildPathSection(
    String key,
    List<Map<String, dynamic>> params,
  ) {
    final isExpanded = _expandedPath[key] ?? true;
    final children = <Component>[
      button(
        classes: 'collapsible-btn${isExpanded ? ' is-expanded' : ''}',
        onClick: () => setState(() => _expandedPath[key] = !isExpanded),
        [
          span([Component.text('Path parameters')]),
          span(classes: 'section-count', [Component.text('${params.length}')]),
        ],
      ),
    ];

    if (isExpanded) {
      for (final parameter in params) {
        final name = parameter['name']?.toString() ?? '';
        final description = parameter['description']?.toString() ?? '';
        final savedValue = (_pathValues[key] ?? {})[name] ?? '';
        children.add(
          div(classes: 'form-field', [
            label([Component.text('$name (path)')]),
            if (description.isNotEmpty) span(classes: 'field-desc', [Component.text(description)]),
            input<String>(
              type: InputType.text,
              classes: 'form-input',
              value: savedValue,
              attributes: {'placeholder': 'Value for {$name}'},
              onInput: (value) => setState(() {
                _pathValues[key] ??= {};
                _pathValues[key]![name] = value;
              }),
            ),
          ]),
        );
      }
    }

    return div(classes: 'path-section', children);
  }

  Component _buildHeadersSection(
    String key,
    List<Map<String, dynamic>> params,
  ) {
    final isExpanded = _expandedHeaders[key] ?? false;
    final children = <Component>[
      button(
        classes: 'collapsible-btn${isExpanded ? ' is-expanded' : ''}',
        onClick: () => setState(() => _expandedHeaders[key] = !isExpanded),
        [
          span([Component.text('Headers')]),
          span(classes: 'section-count', [Component.text('${params.length}')]),
        ],
      ),
    ];

    if (isExpanded) {
      for (final hp in params) {
        final name = hp['name'] as String;
        final desc = hp['description']?.toString() ?? '';
        final schema = hp['schema'] as Map<String, dynamic>? ?? {};
        final type = schema['type']?.toString() ?? 'string';
        final savedVal = (_headerValues[key] ?? {})[name] ?? '';

        children.add(
          div(classes: 'form-field', [
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
          ]),
        );
      }
    }

    return div(classes: 'headers-section', children);
  }

  Component _buildResponseSchemas(Map<String, dynamic> responses) {
    final items = responses.entries.map<Component>((entry) {
      final code = entry.key;
      final resp = entry.value as Map<String, dynamic>;
      final desc = resp['description']?.toString() ?? '';
      final content = resp['content']?['application/json'] as Map<String, dynamic>?;
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
