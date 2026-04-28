import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:html' as html;

class App extends StatefulComponent {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  Map<String, dynamic>? apiData;
  Timer? timer;
  bool isDark = false;
  String searchQuery = '';
  String authHeader = '';
  final Map<String, String> _responses = {};
  final Map<String, bool> _loading = {};
  final Map<String, Map<String, String>> _requestBodyValues = {};
  final Map<String, bool> _expandedEndpoints = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    timer = Timer.periodic(const Duration(seconds: 3), (_) => _loadData());

    try {
      if (html.window.matchMedia('(prefers-color-scheme: dark)').matches) {
        isDark = true;
        _applyTheme();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void _applyTheme() {
    try {
      html.document.documentElement?.setAttribute('data-theme', isDark ? 'dark' : 'light');
    } catch (_) {}
  }

  Future<void> _loadData() async {
    try {
      final resp = await http.get(Uri.parse('/froggy_docs.json'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() => apiData = data as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  Future<void> _executeRequest(String method, String path, bool hasAuth, Map<String, dynamic>? props) async {
    final key = '$method-$path';
    setState(() => _loading[key] = true);

    try {
      final baseUrl = html.window.location.origin;
      final url = '$baseUrl$path';

      final headers = <String, String>{
        'Content-Type': 'application/json',
      };

      if (authHeader.isNotEmpty) {
        headers['Authorization'] = authHeader;
      }

      String body = '{}';
      if (props != null && props.isNotEmpty) {
        final Map<String, dynamic> bodyData = {};
        final savedValues = _requestBodyValues[key] ?? {};
        for (var prop in props.entries) {
          final value = savedValues[prop.key] ?? _getDefaultValue(prop.value['type']);
          if (value.isNotEmpty) {
            bodyData[prop.key] = _parseValue(value, prop.value['type']);
          }
        }
        body = jsonEncode(bodyData);
      }

      http.Response resp;
      switch (method.toUpperCase()) {
        case 'GET':
          resp = await http.get(Uri.parse(url), headers: headers);
          break;
        case 'POST':
          resp = await http.post(Uri.parse(url), headers: headers, body: body);
          break;
        case 'PUT':
          resp = await http.put(Uri.parse(url), headers: headers, body: body);
          break;
        case 'DELETE':
          resp = await http.delete(Uri.parse(url), headers: headers);
          break;
        case 'PATCH':
          resp = await http.patch(Uri.parse(url), headers: headers, body: body);
          break;
        default:
          resp = await http.get(Uri.parse(url), headers: headers);
      }

      setState(() {
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          try {
            _responses[key] = JsonEncoder.withIndent('  ').convert(jsonDecode(resp.body));
          } catch (_) {
            _responses[key] = resp.body;
          }
        } else {
          _responses[key] = 'Error ${resp.statusCode}: ${resp.body}';
        }
      });
    } catch (e) {
      setState(() {
        _responses[key] = 'Error: $e';
      });
    } finally {
      setState(() => _loading[key] = false);
    }
  }

  String _getDefaultValue(String? type) {
    switch (type?.toString().toLowerCase()) {
      case 'number':
        return '0';
      case 'boolean':
        return 'true';
      case 'array':
        return '[]';
      case 'object':
        return '{}';
      default:
        return '';
    }
  }

  dynamic _parseValue(String value, String? type) {
    switch (type?.toString().toLowerCase()) {
      case 'number':
        return num.tryParse(value) ?? 0;
      case 'boolean':
        return value.toLowerCase() == 'true';
      case 'array':
        return [];
      case 'object':
        return {};
      default:
        return value;
    }
  }

  Map<String, List<MapEntry<String, dynamic>>> _getEndpointsByTag() {
    final Map<String, List<MapEntry<String, dynamic>>> byTag = {};
    final paths = apiData?['paths'] as Map<String, dynamic>? ?? {};

    for (var path in paths.entries) {
      for (var method in (path.value as Map<String, dynamic>).entries) {
        final tags = (method.value['tags'] as List?) ?? ['Untagged'];
        for (var tag in tags) {
          byTag.putIfAbsent(tag.toString(), () => []);
          byTag[tag.toString()]!.add(MapEntry(path.key, method));
        }
      }
    }
    return byTag;
  }

  @override
  Component build(BuildContext context) {
    return div(classes: 'app-container', [
      _buildSidebar(),
      _buildMainContent(),
    ]);
  }

  Component _buildSidebar() {
    final byTag = _getEndpointsByTag();

    final filtered = byTag.entries.where((e) {
      if (searchQuery.isEmpty) return true;
      if (e.key.toLowerCase().contains(searchQuery.toLowerCase())) return true;
      return e.value.any((ep) => ep.key.toLowerCase().contains(searchQuery.toLowerCase()));
    }).toList();

    return aside(classes: 'sidebar', [
      div(classes: 'sidebar-header', [
        h2([
          span([text('🐸')], attributes: {'style': 'font-size: 24px;'}),
          text(' FroggyDocs'),
        ]),
      ]),
      div(classes: 'search-container', [
        input(
          type: InputType.text,
          classes: 'search-box',
          attributes: {'placeholder': 'Search tags or endpoints...'},
          onInput: (val) => setState(() => searchQuery = val.toString()),
        ),
      ]),
      nav(classes: 'nav-list', [
        for (var tagGroup in filtered) _buildTagGroup(tagGroup.key, tagGroup.value),
      ]),
    ]);
  }

  Component _buildTagGroup(String tag, List<MapEntry<String, dynamic>> endpoints) {
    final matchesSearch = searchQuery.isEmpty || tag.toLowerCase().contains(searchQuery.toLowerCase());

    // When searching by tag name, show ALL endpoints in that tag
    // When searching by endpoint path, filter endpoints
    final filtered = (searchQuery.isEmpty || matchesSearch)
        ? endpoints
        : endpoints.where((ep) => ep.key.toLowerCase().contains(searchQuery.toLowerCase())).toList();

    if (searchQuery.isNotEmpty && filtered.isEmpty) return div([]);

    return div(classes: 'tag-group', [
      div(classes: 'tag-header', [
        span([text('▶ $tag')]),
      ]),
      div(classes: 'tag-endpoints', [
        for (var ep in filtered)
          a(classes: 'nav-item', href: '#${ep.value.key.toUpperCase()}-${ep.key}', [
            span(classes: 'method-tag ${ep.value.key.toUpperCase()}', [text(ep.value.key.toUpperCase())]),
            span([text(ep.key)]),
          ]),
      ]),
    ]);
  }

  Component _buildMainContent() {
    return div(classes: 'main-content', [
      header(classes: 'header', [
        h1([text((apiData?['info'] as Map<String, dynamic>?)?['title'] as String? ?? 'API Documentation')]),
        button(
          classes: 'theme-toggle',
          [text(isDark ? '☀️' : '🌙')],
          events: {
            'click': (_) => setState(() {
              isDark = !isDark;
              _applyTheme();
            }),
          },
        ),
      ]),
      div(classes: 'settings-section', [
        div([text('Authorization: ')]),
        input(
          type: InputType.text,
          classes: 'auth-input',
          attributes: {'placeholder': 'Bearer token'},
          onInput: (val) => setState(() => authHeader = val.toString()),
        ),
      ]),
      if (apiData == null)
        div(classes: 'api-section', [
          p([text('Loading...')]),
        ])
      else
        _buildApiList(),
    ]);
  }

  Component _buildApiList() {
    final paths = apiData!['paths'] as Map<String, dynamic>? ?? {};
    return div([
      for (var path in paths.entries)
        for (var method in (path.value as Map<String, dynamic>).entries)
          _buildEndpoint(path.key, method.key, method.value),
    ]);
  }

  Component _buildEndpoint(String path, String method, dynamic spec) {
    final props =
        spec['requestBody']?['content']?['application/json']?['schema']?['properties'] as Map<String, dynamic>?;
    final hasAuth = spec['security'] != null;
    final key = '$method-$path';
    final response = _responses[key];
    final isLoading = _loading[key] ?? false;
    final isExpanded = _expandedEndpoints[key] ?? false;
    final savedValues = _requestBodyValues[key] ?? {};

    return section(
      classes: 'api-section',
      attributes: {'id': '${method.toUpperCase()}-$path'},
      [
        div(classes: 'endpoint-header', [
          span(classes: 'method-tag ${method.toUpperCase()}', [text(method.toUpperCase())]),
          span(classes: 'path-text', [text(path)]),
          if (hasAuth) span(classes: 'auth-badge', [text('🔒 Auth')]),
        ]),
        p(classes: 'api-description', [text(spec['summary'] ?? 'No description')]),

        if (props != null && props.isNotEmpty) ...[
          button(
            classes: 'try-it-out-btn',
            [text(isExpanded ? 'Hide Request Body' : 'Show Request Body')],
            events: {'click': (_) => setState(() => _expandedEndpoints[key] = !isExpanded)},
          ),
          if (isExpanded) ...[
            h3(classes: 'section-title', [text('Request Body')]),
            div(classes: 'request-body-form', [
              for (var prop in props.entries)
                div(classes: 'form-field', [
                  label([text(prop.key), text(' (${prop.value['type'] ?? 'string'})')]),
                  if (prop.value['description'] != null && (prop.value['description'] as String).isNotEmpty)
                    span(classes: 'field-desc', [text(prop.value['description'])]),
                  input(
                    type: InputType.text,
                    classes: 'form-input',
                    attributes: {
                      'placeholder': _getDefaultValue(prop.value['type']),
                      'value': savedValues[prop.key] ?? '',
                    },
                    onInput: (val) {
                      setState(() {
                        _requestBodyValues[key] ??= {};
                        _requestBodyValues[key]![prop.key] = val.toString();
                      });
                    },
                  ),
                ]),
            ]),
          ],
        ],

        button(
          classes: 'try-it-out-btn ${props != null && props.isNotEmpty ? 'secondary' : ''}',
          [text(isLoading ? 'Loading...' : 'Try It Out')],
          events: {'click': (_) => _executeRequest(method, path, hasAuth, props)},
        ),

        if (response != null) ...[
          div(classes: 'response-section', [
            h4([text('Response:')]),
            pre(classes: 'response-body', [text(response)]),
          ]),
        ],

        if (props != null && props.isNotEmpty) ...[
          h3(classes: 'section-title', [text('Parameters')]),
          table(classes: 'params-table', [
            thead([
              tr([
                th([text('Field')]),
                th([text('Type')]),
                th([text('Description')]),
              ]),
            ]),
            tbody([
              for (var prop in props.entries)
                tr([
                  td([
                    b([text(prop.key)]),
                  ]),
                  td([
                    span(classes: 'type-label', [text((prop.value['type'] ?? 'string').toString())]),
                  ]),
                  td([text((prop.value['description'] ?? '-').toString())]),
                ]),
            ]),
          ]),
        ],
      ],
    );
  }
}
