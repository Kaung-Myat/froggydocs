import 'dart:convert';
import 'dart:io';
import 'package:froggy_docs/froggy_docs.dart';
import 'package:test/test.dart';

void main() {
  late ParserEngine parser;

  setUp(() {
    parser = ParserEngine();
    parser.setOutputPath('test_output/froggy_docs.json');
    parser.clearRegistry();
  });

  tearDown(() {
    final testDir = Directory('test_output');
    if (testDir.existsSync()) {
      testDir.deleteSync(recursive: true);
    }
  });

  group('ParserEngine', () {
    test('can be instantiated', () {
      expect(parser, isNotNull);
    });

    test('can parse basic @api annotation', () {
      final testFile = File('test_output/test_api.dart');
      testFile.parent.createSync(recursive: true);
      testFile.writeAsStringSync('''
// @api GET /api/users
// @desc List all users
// @tag Users
''');

      parser.parseFile(testFile.path);
      final spec = parser.generateSpec();

      expect(spec['paths'], contains('/api/users'));
      expect(
        spec['paths']['/api/users']['get']['summary'],
        equals('List all users'),
      );
      expect(spec['paths']['/api/users']['get']['tags'], equals(['Users']));
    });

    test('can parse @body annotation', () {
      final testFile = File('test_output/test_body.dart');
      testFile.parent.createSync(recursive: true);
      testFile.writeAsStringSync('''
// @api POST /api/users
// @desc Create a user
// @body name string User full name
// @body email string User email address
// @body age number User age
''');

      parser.parseFile(testFile.path);
      final spec = parser.generateSpec();

      final requestBody = spec['paths']['/api/users']['post']['requestBody'];
      expect(requestBody, isNotNull);
      expect(requestBody['content']['application/json'], isNotNull);
      final props =
          requestBody['content']['application/json']['schema']['properties'];
      expect(props['name']['type'], equals('string'));
      expect(props['email']['type'], equals('string'));
      expect(props['age']['type'], equals('number'));
    });

    test('can parse @auth annotation', () {
      final testFile = File('test_output/test_auth.dart');
      testFile.parent.createSync(recursive: true);
      testFile.writeAsStringSync('''
// @api DELETE /api/users/1
// @desc Delete a user
// @auth
''');

      parser.parseFile(testFile.path);
      final spec = parser.generateSpec();

      expect(spec['paths']['/api/users/1']['delete']['security'], isNotNull);
    });

    test('can parse @tag annotation', () {
      final testFile = File('test_output/test_tag.dart');
      testFile.parent.createSync(recursive: true);
      testFile.writeAsStringSync('''
// @api GET /api/products
// @desc List products
// @tag Products
// @tag Catalog
''');

      parser.parseFile(testFile.path);
      final spec = parser.generateSpec();

      expect(
        spec['paths']['/api/products']['get']['tags'],
        contains('Products'),
      );
      expect(
        spec['paths']['/api/products']['get']['tags'],
        contains('Catalog'),
      );
    });

    test('can parse @body-json annotation', () {
      final testFile = File('test_output/test_bodyjson.dart');
      testFile.parent.createSync(recursive: true);
      testFile.writeAsStringSync('''
// @api POST /api/login
// @desc User login
// @body-json
// {"username": "admin", "password": "secret"}
''');

      parser.parseFile(testFile.path);
      final spec = parser.generateSpec();

      final props =
          spec['paths']['/api/login']['post']['requestBody']['content']['application/json']['schema']['properties'];
      expect(props['username']['type'], equals('string'));
      expect(props['password']['type'], equals('string'));
    });

    test('can parse @file annotation', () {
      final testFile = File('test_output/test_file.dart');
      testFile.parent.createSync(recursive: true);
      testFile.writeAsStringSync('''
// @api POST /api/upload
// @desc Upload user avatar
// @file avatar binary User profile picture
// @file document pdf Optional PDF attachment
''');

      parser.parseFile(testFile.path);
      final spec = parser.generateSpec();

      final requestBody = spec['paths']['/api/upload']['post']['requestBody'];
      expect(requestBody, isNotNull);
      expect(requestBody['content']['multipart/form-data'], isNotNull);
      final props =
          requestBody['content']['multipart/form-data']['schema']['properties'];
      expect(props['avatar']['type'], equals('string'));
      expect(props['avatar']['format'], equals('binary'));
      expect(props['avatar']['description'], equals('User profile picture'));
      expect(props['document']['type'], equals('string'));
      expect(props['document']['format'], equals('binary'));
      expect(
        props['document']['description'],
        equals('Optional PDF attachment'),
      );
    });

    test('can parse multiple files as a binary array', () {
      final file = File('test_output/multi_upload.js');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('''
// @api POST /api/media
// @file media binary[] Multiple image files
''');

      parser.parseFile(file.path);
      final property = parser
          .generateSpec()['paths']['/api/media']['post']['requestBody']['content']['multipart/form-data']['schema']['properties']['media'];

      expect(property['type'], equals('array'));
      expect(property['items']['type'], equals('string'));
      expect(property['items']['format'], equals('binary'));
    });

    test(
      'can parse mixed @body and @file (multipart with text and file fields)',
      () {
        final testFile = File('test_output/test_mixed.dart');
        testFile.parent.createSync(recursive: true);
        testFile.writeAsStringSync('''
// @api POST /api/profile
// @desc Update user profile with avatar
// @body name string User display name
// @body bio string User biography
// @file avatar binary Profile picture
''');

        parser.parseFile(testFile.path);
        final spec = parser.generateSpec();

        final requestBody =
            spec['paths']['/api/profile']['post']['requestBody'];
        expect(requestBody['content']['multipart/form-data'], isNotNull);
        final props =
            requestBody['content']['multipart/form-data']['schema']['properties'];
        expect(props['name']['type'], equals('string'));
        expect(props['name']['description'], equals('User display name'));
        expect(props['bio']['type'], equals('string'));
        expect(props['avatar']['format'], equals('binary'));
      },
    );

    test('can parse @response annotation', () {
      final testFile = File('test_output/test_response.dart');
      testFile.parent.createSync(recursive: true);
      testFile.writeAsStringSync('''
// @api POST /api/users
// @desc Create a new user
// @response 201 object User created successfully
// @response-json {"id": 1, "name": "Alice"}
''');

      parser.parseFile(testFile.path);
      final spec = parser.generateSpec();

      final responses = spec['paths']['/api/users']['post']['responses'];
      expect(responses['201'], isNotNull);
      expect(
        responses['201']['description'],
        equals('User created successfully'),
      );
      expect(
        responses['201']['content']['application/json']['schema']['type'],
        equals('object'),
      );
      expect(
        responses['201']['content']['application/json']['example']['id'],
        equals(1),
      );
      expect(
        responses['201']['content']['application/json']['example']['name'],
        equals('Alice'),
      );
    });

    test('can parse @response with array type', () {
      final testFile = File('test_output/test_response_array.dart');
      testFile.parent.createSync(recursive: true);
      testFile.writeAsStringSync('''
// @api GET /api/users
// @desc List all users
// @response 200 array List of users
// @response-json [{"id": 1}, {"id": 2}]
''');

      parser.parseFile(testFile.path);
      final spec = parser.generateSpec();

      final responses = spec['paths']['/api/users']['get']['responses'];
      expect(
        responses['200']['content']['application/json']['schema']['type'],
        equals('array'),
      );
      expect(
        responses['200']['content']['application/json']['example'],
        isA<List>(),
      );
    });

    test('can parse @query annotation', () {
      final testFile = File('test_output/test_query.dart');
      testFile.parent.createSync(recursive: true);
      testFile.writeAsStringSync('''
// @api GET /api/users
// @desc List users with pagination
// @query page int Page number (default: 1)
// @query limit int Items per page (default: 10)
// @query search string Search term
''');

      parser.parseFile(testFile.path);
      final spec = parser.generateSpec();

      final params = spec['paths']['/api/users']['get']['parameters'] as List;
      expect(params.length, equals(3));

      final pageParam = params.firstWhere((p) => p['name'] == 'page');
      expect(pageParam['in'], equals('query'));
      expect(pageParam['schema']['type'], equals('int'));
      expect(pageParam['schema']['default'], equals(1));
      expect(pageParam['description'], equals('Page number'));

      final searchParam = params.firstWhere((p) => p['name'] == 'search');
      expect(searchParam['schema']['default'], isNull);
    });

    test('can parse @header annotation', () {
      final testFile = File('test_output/test_header.dart');
      testFile.parent.createSync(recursive: true);
      testFile.writeAsStringSync('''
// @api GET /api/data
// @desc Get data with custom headers
// @header X-Request-ID string Optional trace ID
// @header X-Api-Version string API version
''');

      parser.parseFile(testFile.path);
      final spec = parser.generateSpec();

      final params = spec['paths']['/api/data']['get']['parameters'] as List;
      final headerParams = params.where((p) => p['in'] == 'header').toList();
      expect(headerParams.length, equals(2));

      final requestIdParam = headerParams.firstWhere(
        (p) => p['name'] == 'X-Request-ID',
      );
      expect(requestIdParam['description'], equals('Optional trace ID'));
    });

    test('handles Python-style comments', () {
      final testFile = File('test_output/test_python.py');
      testFile.parent.createSync(recursive: true);
      testFile.writeAsStringSync('''
# @api GET /api/items
# @desc List items from Python API
# @tag Items
''');

      parser.parseFile(testFile.path);
      final spec = parser.generateSpec();

      expect(spec['paths'], contains('/api/items'));
      expect(
        spec['paths']['/api/items']['get']['summary'],
        equals('List items from Python API'),
      );
    });

    test('handles Go-style comments', () {
      final testFile = File('test_output/test_go.go');
      testFile.parent.createSync(recursive: true);
      testFile.writeAsStringSync('''
// @api POST /api/items
// @desc Create item in Go
// @body title string Item title
''');

      parser.parseFile(testFile.path);
      final spec = parser.generateSpec();

      expect(spec['paths'], contains('/api/items'));
    });

    test('ignores unsupported file extensions', () {
      final testFile = File('test_output/test_unknown.xyz');
      testFile.parent.createSync(recursive: true);
      testFile.writeAsStringSync('''
// @api GET /api/ignored
// @desc This should be ignored
''');

      parser.parseFile(testFile.path);
      final spec = parser.generateSpec();

      expect(spec['paths'], isNot(contains('/api/ignored')));
    });

    test('can remove file from registry', () {
      final testFile = File('test_output/test_remove.dart');
      testFile.parent.createSync(recursive: true);
      testFile.writeAsStringSync('''
// @api GET /api/temp
// @desc Temporary endpoint
''');

      parser.parseFile(testFile.path);
      expect(parser.pathCount, greaterThan(0));

      parser.removeFile(testFile.path);
      expect(parser.pathCount, equals(0));
    });

    test('clears registry', () {
      final testFile1 = File('test_output/test_clear1.dart');
      final testFile2 = File('test_output/test_clear2.dart');
      testFile1.parent.createSync(recursive: true);
      testFile1.writeAsStringSync('// @api GET /api/one\n// @desc One');
      testFile2.writeAsStringSync('// @api GET /api/two\n// @desc Two');

      parser.parseFile(testFile1.path);
      parser.parseFile(testFile2.path);
      expect(parser.pathCount, equals(2));

      parser.clearRegistry();
      expect(parser.pathCount, equals(0));
    });

    test('output path is configurable', () {
      expect(parser.outputPath, equals('test_output/froggy_docs.json'));
      parser.setOutputPath('custom/path/spec.json');
      expect(parser.outputPath, equals('custom/path/spec.json'));
    });

    test('generates OpenAPI 3.0.0 compliant spec', () {
      final testFile = File('test_output/test_openapi.dart');
      testFile.parent.createSync(recursive: true);
      testFile.writeAsStringSync('''
// @api GET /api/test
// @desc Test endpoint
// @tag Test
''');

      parser.parseFile(testFile.path);
      final spec = parser.generateSpec();

      expect(spec['openapi'], equals('3.0.0'));
      expect(spec['info'], isNotNull);
      expect(spec['info']['title'], isNotNull);
      expect(spec['info']['version'], isNotNull);
      expect(spec['paths'], isNotNull);
      expect(spec['components'], isNotNull);
      expect(
        spec['components']['securitySchemes']['bearerAuth']['type'],
        equals('http'),
      );
    });

    test('handles @body-file annotation', () {
      final jsonFile = File('test_output/mock_body.json');
      jsonFile.parent.createSync(recursive: true);
      jsonFile.writeAsStringSync('{"email": "test@example.com", "age": 25}');

      final testFile = File('test_output/test_bodyfile.dart');
      testFile.writeAsStringSync('''
// @api POST /api/import
// @desc Import from body file
// @body-file mock_body.json
''');

      parser.parseFile(testFile.path);
      final spec = parser.generateSpec();

      final props =
          spec['paths']['/api/import']['post']['requestBody']['content']['application/json']['schema']['properties'];
      expect(props['email']['type'], equals('string'));
      expect(props['age']['type'], equals('number'));
    });

    test('handles multiple response codes', () {
      final testFile = File('test_output/test_multi_response.dart');
      testFile.parent.createSync(recursive: true);
      testFile.writeAsStringSync('''
// @api POST /api/users
// @desc Create user
// @response 201 object User created
// @response-json {"id": 1}
// @response 400 object Bad request
// @response-json {"error": "Invalid input"}
''');

      parser.parseFile(testFile.path);
      final spec = parser.generateSpec();

      final responses = spec['paths']['/api/users']['post']['responses'];
      expect(responses.containsKey('201'), isTrue);
      expect(responses.containsKey('400'), isTrue);
      expect(
        responses['400']['content']['application/json']['example']['error'],
        equals('Invalid input'),
      );
    });

    test('normalizes colon path parameters and declares them in OpenAPI', () {
      final testFile = File('test_output/test_path.dart');
      testFile.parent.createSync(recursive: true);
      testFile.writeAsStringSync('''
// @api GET /api/users/:id
// @desc Get one user
''');

      parser.parseFile(testFile.path);
      final spec = parser.generateSpec();
      final endpoint = spec['paths']['/api/users/{id}']['get'];
      final parameters = endpoint['parameters'] as List;

      expect(
        parameters,
        contains(
          predicate((dynamic parameter) {
            if (parameter is! Map) return false;
            return parameter['name'] == 'id' &&
                parameter['in'] == 'path' &&
                parameter['required'] == true;
          }),
        ),
      );
    });

    test('can batch parse files and write the output only once', () {
      final firstFile = File('test_output/first.dart');
      final secondFile = File('test_output/second.dart');
      firstFile.parent.createSync(recursive: true);
      firstFile.writeAsStringSync('// @api GET /api/first');
      secondFile.writeAsStringSync('// @api GET /api/second');

      parser.parseFile(firstFile.path, writeOutput: false);
      parser.parseFile(secondFile.path, writeOutput: false);
      expect(File(parser.outputPath).existsSync(), isFalse);

      parser.writeOutput();
      final output = jsonDecode(File(parser.outputPath).readAsStringSync());
      expect(output['paths'], containsPair('/api/first', isA<Map>()));
      expect(output['paths'], containsPair('/api/second', isA<Map>()));
    });

    test('removes tags that no longer exist in the registry', () {
      final testFile = File('test_output/tagged.dart');
      testFile.parent.createSync(recursive: true);
      testFile.writeAsStringSync('''
// @api GET /api/tagged
// @tag Temporary
''');

      parser.parseFile(testFile.path);
      expect(parser.generateSpec()['tags'], isNotEmpty);

      parser.removeFile(testFile.path);
      expect(parser.generateSpec(), isNot(contains('tags')));
    });
  });

  group('FroggyConfig', () {
    test('parses deployment environments and production safety', () {
      final config = FroggyConfig.fromMap({
        'project': {'title': 'Team API', 'version': '2.0.0'},
        'docs': {
          'basePath': 'docs/api',
          'outputDirectory': 'public/docs',
          'defaultEnvironment': 'Staging',
        },
        'servers': [
          {
            'name': 'Staging',
            'url': 'https://staging.example.com',
            'environment': 'staging',
          },
          {
            'name': 'Production',
            'url': 'https://api.example.com',
            'environment': 'production',
            'readOnly': true,
          },
        ],
      });

      expect(config.title, equals('Team API'));
      expect(config.basePath, equals('/docs/api/'));
      expect(config.outputDirectory, equals('public/docs'));
      expect(config.servers, hasLength(2));
      expect(config.servers.last.isProduction, isTrue);
      expect(config.servers.last.readOnly, isTrue);
      expect(config.servers.last.confirmMutations, isTrue);
    });

    test('adds configured metadata and servers to the OpenAPI document', () {
      parser.configureMetadata(
        title: 'Configured API',
        version: '3.0.0',
        description: 'Team documentation',
        servers: const [
          {
            'url': 'https://api.example.com',
            'description': 'Production',
            'x-read-only': true,
          },
        ],
        runtimeExtension: const {
          'basePath': '/docs/api/',
          'defaultEnvironment': 'Production',
        },
      );

      final spec = parser.generateSpec();
      expect(spec['info']['title'], equals('Configured API'));
      expect(spec['servers'], hasLength(1));
      expect(spec['x-froggy-docs']['basePath'], equals('/docs/api/'));
    });

    test('parses an OpenAPI input source and polling configuration', () {
      final config = FroggyConfig.fromMap({
        'input': {
          'specUrl': 'https://api.example.com/openapi.json',
          'specHeaderEnv': 'OPENAPI_HEADER',
          'pollIntervalSeconds': 30,
        },
      });

      expect(config.specPath, isEmpty);
      expect(config.specUrl, equals('https://api.example.com/openapi.json'));
      expect(config.specHeaderEnvironment, equals('OPENAPI_HEADER'));
      expect(config.specPollIntervalSeconds, equals(30));
    });
  });

  group('OpenApiSpecLoader', () {
    test('loads YAML and adds FroggyDocs runtime configuration', () {
      final loader = OpenApiSpecLoader(
        basePath: '/docs/api/',
        defaultEnvironment: 'Staging',
      );
      addTearDown(loader.close);

      final spec = loader.parse(
        utf8.encode('''
openapi: 3.1.0
info:
  title: Imported API
  version: 2.0.0
paths:
  /users:
    get:
      responses:
        "200":
          description: Success
'''),
        source: 'openapi.yaml',
      );

      expect(spec['openapi'], equals('3.1.0'));
      expect(spec['paths'], contains('/users'));
      expect(spec['x-froggy-docs']['basePath'], equals('/docs/api/'));
      expect(spec['x-froggy-docs']['defaultEnvironment'], equals('Staging'));
    });

    test('resolves internal component references for the UI', () {
      final loader = OpenApiSpecLoader();
      addTearDown(loader.close);
      final spec = loader.parse(
        utf8.encode(
          jsonEncode({
            'openapi': '3.0.3',
            'info': {'title': 'Reference API', 'version': '1.0.0'},
            'paths': {
              '/users': {
                'post': {
                  'requestBody': {
                    'content': {
                      'application/json': {
                        'schema': {r'$ref': '#/components/schemas/User'},
                      },
                    },
                  },
                  'responses': {
                    '200': {'description': 'Success'},
                  },
                },
              },
            },
            'components': {
              'schemas': {
                'User': {
                  'type': 'object',
                  'properties': {
                    'name': {'type': 'string'},
                  },
                },
              },
            },
          }),
        ),
        source: 'openapi.json',
      );

      final schema =
          spec['paths']['/users']['post']['requestBody']['content']['application/json']['schema'];
      expect(schema['type'], equals('object'));
      expect(schema['properties']['name']['type'], equals('string'));
    });

    test('normalizes path parameters and inherited security for the UI', () {
      final loader = OpenApiSpecLoader();
      addTearDown(loader.close);
      final spec = loader.parse(
        utf8.encode(
          jsonEncode({
            'openapi': '3.0.3',
            'info': {'title': 'Normalized API', 'version': '1.0.0'},
            'security': [
              {'bearerAuth': <dynamic>[]},
            ],
            'paths': {
              '/users/{id}': {
                'summary': 'User operations',
                'parameters': [
                  {
                    'name': 'id',
                    'in': 'path',
                    'required': true,
                    'schema': {'type': 'string'},
                  },
                ],
                'get': {
                  'parameters': [
                    {
                      'name': 'expand',
                      'in': 'query',
                      'schema': {'type': 'boolean'},
                    },
                  ],
                  'responses': {
                    '200': {
                      'description': 'Success',
                      'content': {
                        'application/problem+json': {
                          'examples': {
                            'default': {
                              'value': {'id': '123'},
                            },
                          },
                        },
                      },
                    },
                  },
                },
              },
            },
          }),
        ),
        source: 'normalized.json',
      );

      final pathItem = spec['paths']['/users/{id}'];
      expect(pathItem.keys, equals(['get']));
      expect(pathItem['get']['parameters'], hasLength(2));
      expect(pathItem['get']['security'], isNotEmpty);
      expect(
        pathItem['get']['responses']['200']['content']['application/json']['example']['id'],
        equals('123'),
      );
    });

    test('rejects Swagger 2.0 and unresolved references', () {
      final loader = OpenApiSpecLoader();
      addTearDown(loader.close);

      expect(
        () => loader.parse(
          utf8.encode(
            jsonEncode({
              'swagger': '2.0',
              'info': {'title': 'Legacy', 'version': '1.0.0'},
              'paths': {},
            }),
          ),
          source: 'swagger.json',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => loader.parse(
          utf8.encode(
            jsonEncode({
              'openapi': '3.0.3',
              'info': {'title': 'Broken', 'version': '1.0.0'},
              'paths': {},
              'components': {
                'schemas': {
                  'Broken': {r'$ref': '#/components/schemas/Missing'},
                },
              },
            }),
          ),
          source: 'broken.json',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('downloads a protected remote specification', () async {
      String? receivedAuthorization;
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) {
        receivedAuthorization = request.headers.value('authorization');
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'openapi': '3.0.3',
              'info': {'title': 'Remote API', 'version': '1.0.0'},
              'paths': {},
            }),
          )
          ..close();
      });

      final loader = OpenApiSpecLoader();
      try {
        final spec = await loader.loadUrl(
          Uri.parse('http://127.0.0.1:${upstream.port}/openapi.json'),
          headers: const {'Authorization': 'Bearer test-token'},
        );
        expect(spec['info']['title'], equals('Remote API'));
        expect(receivedAuthorization, equals('Bearer test-token'));
      } finally {
        loader.close();
        await upstream.close(force: true);
      }
    });
  });

  group('WebServer', () {
    test('serves the generated project specification explicitly', () async {
      final specification = File('test_output/project-spec.json');
      specification.parent.createSync(recursive: true);
      specification.writeAsStringSync('{"source":"project"}');

      final server = await startServer(
        port: 0,
        specificationPath: specification.path,
      );
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse(
            'http://${server.address.host}:${server.port}/froggy_docs.json',
          ),
        );
        final response = await request.close();
        final body = await utf8.decoder.bind(response).join();

        expect(response.statusCode, equals(HttpStatus.ok));
        expect(jsonDecode(body), equals({'source': 'project'}));
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    });

    test('proxies API paths that do not start with /api', () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'method': request.method,
              'path': request.uri.path,
              'query': request.uri.query,
              'body': body,
            }),
          )
          ..close();
      });
      final server = await startServer(
        port: 0,
        proxyUrl: 'http://127.0.0.1:${upstream.port}',
      );
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse(
            'http://${server.address.host}:${server.port}/v1/items?draft=true',
          ),
        );
        request.headers.contentType = ContentType.json;
        request.write('{"name":"frog"}');
        final response = await request.close();
        final decoded = jsonDecode(await utf8.decoder.bind(response).join());

        expect(response.statusCode, equals(HttpStatus.ok));
        expect(decoded['method'], equals('POST'));
        expect(decoded['path'], equals('/v1/items'));
        expect(decoded['query'], equals('draft=true'));
        expect(decoded['body'], equals('{"name":"frog"}'));
      } finally {
        client.close(force: true);
        await server.close(force: true);
        await upstream.close(force: true);
      }
    });
  });
}
