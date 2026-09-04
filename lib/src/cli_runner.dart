import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:froggy_docs/src/froggy_config.dart';
import 'package:froggy_docs/src/openapi_spec_loader.dart';
import 'package:froggy_docs/src/parser_engine.dart';
import 'package:froggy_docs/src/specification_watcher.dart';
import 'package:froggy_docs/src/watcher_engine.dart';
import 'package:froggy_docs/src/web_server.dart';
import 'package:froggy_docs/src/version.dart';
import 'package:path/path.dart' as p;

class CliRunner {
  Future<void> run(List<String> arguments) async {
    final parser = ArgParser()
      ..addCommand('watch')
      ..addCommand('serve')
      ..addCommand('build')
      ..addOption(
        'port',
        abbr: 'p',
        help: 'Port for server',
        defaultsTo: '8080',
      )
      ..addOption(
        'proxy',
        abbr: 'x',
        help: 'Proxy API requests to this URL (e.g., http://localhost:3000)',
        defaultsTo: '',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help:
            'Specification JSON path, or static directory for build when the path does not end in .json',
        defaultsTo: 'frontend/web/froggy_docs.json',
      )
      ..addOption(
        'dist',
        help: 'Static deployment output directory (default: dist)',
        defaultsTo: '',
      )
      ..addOption(
        'base-path',
        help: 'Documentation URL base path (e.g., /docs/api/)',
        defaultsTo: '',
      )
      ..addOption(
        'ignore',
        help:
            'Glob pattern for paths to exclude from watching (e.g., "**/*.g.dart")',
        defaultsTo: '',
      )
      ..addOption(
        'project',
        help: 'Project directory to scan (default: current directory)',
        defaultsTo: '',
      )
      ..addOption(
        'spec',
        help: 'Local OpenAPI 3.0/3.1 JSON or YAML file',
        defaultsTo: '',
      )
      ..addOption(
        'spec-url',
        help: 'HTTP/HTTPS URL that returns an OpenAPI 3.0/3.1 document',
        defaultsTo: '',
      )
      ..addOption(
        'spec-header-env',
        help: 'Environment variable containing one Name: Value request header',
        defaultsTo: '',
      )
      ..addOption(
        'spec-poll-interval',
        help: 'Seconds between --spec-url reload checks (default: 10)',
        defaultsTo: '',
      )
      ..addFlag(
        'help',
        abbr: 'h',
        help: 'Show this help message',
        negatable: false,
      )
      ..addFlag(
        'version',
        abbr: 'v',
        help: 'Show the FroggyDocs version',
        negatable: false,
      );

    try {
      final results = parser.parse(arguments);
      if (results['help'] == true) {
        _printHelp();
        return;
      }
      if (results['version'] == true) {
        print(froggyDocsVersion);
        return;
      }
      final projectPath = results['project'] as String;
      final specArgument = results['spec'] as String;
      final specUrlArgument = results['spec-url'] as String;
      final explicitSources = [
        projectPath,
        specArgument,
        specUrlArgument,
      ].where((value) => value.trim().isNotEmpty).length;
      if (explicitSources > 1) {
        throw const FormatException(
          'Choose only one input source: --project, --spec, or --spec-url.',
        );
      }
      if (projectPath.isNotEmpty) {
        final resolvedProjectPath = p.absolute(projectPath);
        if (!Directory(resolvedProjectPath).existsSync()) {
          throw FileSystemException(
            'Project directory does not exist',
            resolvedProjectPath,
          );
        }
        Directory.current = resolvedProjectPath;
      }

      final config = FroggyConfig.load();
      final source = _resolveInputSource(
        projectPath: projectPath,
        specArgument: specArgument,
        specUrlArgument: specUrlArgument,
        config: config,
      );
      final explicitOutput = results.wasParsed('output');
      final outputArgument = results['output'] as String;
      final outputIsJson = outputArgument.toLowerCase().endsWith('.json');
      final outputPath = explicitOutput && outputIsJson
          ? outputArgument
          : config.specOutput;
      final explicitDist = results['dist'] as String;
      final distPath = explicitDist.isNotEmpty
          ? explicitDist
          : (explicitOutput && !outputIsJson
                ? outputArgument
                : config.outputDirectory);
      final basePathArgument = results['base-path'] as String;
      final basePath = basePathArgument.isNotEmpty
          ? normalizeBasePath(basePathArgument)
          : config.basePath;
      final ignorePattern = results['ignore'] as String;
      final headerEnvironmentArgument = results['spec-header-env'] as String;
      final headerEnvironment = headerEnvironmentArgument.isNotEmpty
          ? headerEnvironmentArgument
          : (source.kind == _InputKind.url ? config.specHeaderEnvironment : '');
      final remoteHeaders = _loadSpecHeaders(headerEnvironment, source);
      final pollArgument = results['spec-poll-interval'] as String;
      final pollIntervalSeconds = pollArgument.isNotEmpty
          ? int.tryParse(pollArgument)
          : config.specPollIntervalSeconds;
      if (pollIntervalSeconds == null || pollIntervalSeconds < 2) {
        throw const FormatException(
          '--spec-poll-interval must be an integer of at least 2 seconds.',
        );
      }

      if (results.command?.name == 'watch') {
        if (source.kind == _InputKind.annotations) {
          print('🐸 FroggyDocs is watching your API project...');
          await WatcherEngine(
            outputPath: outputPath,
            ignorePattern: ignorePattern,
            config: config,
            basePath: basePath,
          ).startWatching(Directory.current.path);
        } else {
          final context = await _loadExternalSpecification(
            source,
            config,
            basePath,
            outputPath,
            remoteHeaders,
          );
          await _startExternalWatcher(
            context,
            pollIntervalSeconds: pollIntervalSeconds,
          );
        }
      } else if (results.command?.name == 'serve') {
        final port = results.wasParsed('port')
            ? int.parse(results['port'] as String)
            : config.port;
        final proxyArgument = results['proxy'] as String;
        final proxyUrl = proxyArgument.isNotEmpty
            ? proxyArgument
            : config.proxyUrl;

        _ExternalSpecContext? externalContext;
        if (source.kind == _InputKind.annotations) {
          await _generateSpecification(
            config,
            outputPath,
            Directory.current.path,
            basePath: basePath,
          );
        } else {
          externalContext = await _loadExternalSpecification(
            source,
            config,
            basePath,
            outputPath,
            remoteHeaders,
          );
        }
        print('🐸 Starting FroggyDocs server with live reload...');
        if (proxyUrl.isNotEmpty) {
          print(
            '🔄 Proxy enabled: API requests will be forwarded to $proxyUrl',
          );
        }
        await startServer(
          port: port,
          proxyUrl: proxyUrl,
          basePath: basePath,
          specificationPath: outputPath,
        );
        if (externalContext == null) {
          await WatcherEngine(
            outputPath: outputPath,
            ignorePattern: ignorePattern,
            config: config,
            basePath: basePath,
          ).startWatching(Directory.current.path);
        } else {
          await _startExternalWatcher(
            externalContext,
            pollIntervalSeconds: pollIntervalSeconds,
          );
        }
      } else if (results.command?.name == 'build') {
        print('🐸 Building deployable FroggyDocs site...');
        late final File specFile;
        OpenApiSpecLoader? externalLoader;
        if (source.kind == _InputKind.annotations) {
          specFile = await _generateSpecification(
            config,
            outputPath,
            Directory.current.path,
            basePath: basePath,
            excludedDirectory: distPath,
          );
        } else {
          final context = await _loadExternalSpecification(
            source,
            config,
            basePath,
            outputPath,
            remoteHeaders,
          );
          specFile = context.outputFile;
          externalLoader = context.loader;
        }
        try {
          await _exportStaticSite(specFile, distPath);
        } finally {
          externalLoader?.close();
        }
        print('✅ Build complete. Static site: ${p.absolute(distPath)}');
        print('📄 Specification: ${p.absolute(outputPath)}');
        print('🌐 Deployment base path: $basePath');
      } else {
        _printHelp();
      }
    } catch (e) {
      print('Error: ${e.toString()}');
      exitCode = 1;
    }
  }

  _InputSource _resolveInputSource({
    required String projectPath,
    required String specArgument,
    required String specUrlArgument,
    required FroggyConfig config,
  }) {
    if (specArgument.trim().isNotEmpty) {
      return _InputSource(_InputKind.file, p.absolute(specArgument.trim()));
    }
    if (specUrlArgument.trim().isNotEmpty) {
      return _InputSource(_InputKind.url, specUrlArgument.trim());
    }
    if (projectPath.trim().isNotEmpty) {
      return const _InputSource(_InputKind.annotations, '');
    }

    final configuredSources = [
      config.specPath,
      config.specUrl,
    ].where((value) => value.trim().isNotEmpty).length;
    if (configuredSources > 1) {
      throw const FormatException(
        'froggy_docs.yaml input must define only one of spec or specUrl.',
      );
    }
    if (config.specPath.trim().isNotEmpty) {
      return _InputSource(_InputKind.file, p.absolute(config.specPath.trim()));
    }
    if (config.specUrl.trim().isNotEmpty) {
      return _InputSource(_InputKind.url, config.specUrl.trim());
    }
    return const _InputSource(_InputKind.annotations, '');
  }

  Map<String, String> _loadSpecHeaders(
    String environmentName,
    _InputSource source,
  ) {
    if (environmentName.trim().isEmpty) return const {};
    if (source.kind != _InputKind.url) {
      throw const FormatException(
        '--spec-header-env can only be used with --spec-url.',
      );
    }
    final rawHeader = Platform.environment[environmentName.trim()];
    if (rawHeader == null || rawHeader.trim().isEmpty) {
      throw FormatException(
        'Environment variable ${environmentName.trim()} is missing or empty.',
      );
    }
    if (rawHeader.contains('\n') || rawHeader.contains('\r')) {
      throw const FormatException(
        'Specification request header cannot contain newlines.',
      );
    }
    final separator = rawHeader.indexOf(':');
    if (separator <= 0 || separator == rawHeader.length - 1) {
      throw FormatException(
        '${environmentName.trim()} must contain a header in Name: Value format.',
      );
    }
    return {
      rawHeader.substring(0, separator).trim(): rawHeader
          .substring(separator + 1)
          .trim(),
    };
  }

  Future<_ExternalSpecContext> _loadExternalSpecification(
    _InputSource source,
    FroggyConfig config,
    String basePath,
    String outputPath,
    Map<String, String> headers,
  ) async {
    if (source.kind == _InputKind.file &&
        p.equals(p.absolute(source.value), p.absolute(outputPath))) {
      throw const FormatException(
        'The generated --output path must be different from the --spec source file.',
      );
    }
    final loader = OpenApiSpecLoader(
      basePath: basePath,
      defaultEnvironment: config.defaultEnvironment,
      configuredServers: config.servers
          .map((server) => server.toOpenApi())
          .toList(),
    );
    try {
      final specification = source.kind == _InputKind.file
          ? await loader.loadFile(source.value)
          : await loader.loadUrl(Uri.parse(source.value), headers: headers);
      await loader.write(specification, outputPath);
      print('Loaded OpenAPI specification from ${source.value}');
      return _ExternalSpecContext(
        source: source,
        loader: loader,
        outputFile: File(p.absolute(outputPath)),
        headers: headers,
      );
    } catch (_) {
      loader.close();
      rethrow;
    }
  }

  Future<void> _startExternalWatcher(
    _ExternalSpecContext context, {
    required int pollIntervalSeconds,
  }) async {
    final watcher = SpecificationWatcher(
      loader: context.loader,
      outputPath: context.outputFile.path,
    );
    if (context.source.kind == _InputKind.file) {
      await watcher.watchFile(context.source.value);
    } else {
      watcher.watchUrl(
        Uri.parse(context.source.value),
        headers: context.headers,
        interval: Duration(seconds: pollIntervalSeconds),
      );
    }
  }

  Future<File> _generateSpecification(
    FroggyConfig config,
    String outputPath,
    String directoryPath, {
    String? basePath,
    String? excludedDirectory,
  }) async {
    final parser = ParserEngine();
    final runtimeExtension = Map<String, dynamic>.from(config.runtimeExtension);
    if (basePath != null) runtimeExtension['basePath'] = basePath;
    parser.setOutputPath(outputPath);
    parser.configureMetadata(
      title: config.title,
      version: config.version,
      description: config.description,
      servers: config.servers.map((server) => server.toOpenApi()).toList(),
      runtimeExtension: runtimeExtension,
    );
    await _scanProject(
      parser,
      directoryPath,
      excludedDirectory: excludedDirectory,
    );
    return File(outputPath);
  }

  Future<void> _scanProject(
    ParserEngine parser,
    String directoryPath, {
    String? excludedDirectory,
  }) async {
    final dir = Directory(directoryPath);
    final excludedPath = excludedDirectory == null
        ? null
        : p.absolute(excludedDirectory);
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final absolutePath = p.absolute(entity.path);
      if (excludedPath != null && p.isWithin(excludedPath, absolutePath)) {
        continue;
      }
      final normalizedPath = entity.path.replaceAll('\\', '/');
      if (!_shouldIgnore(normalizedPath)) {
        parser.parseFile(entity.path, writeOutput: false);
      }
    }
    parser.writeOutput();
  }

  Future<void> _exportStaticSite(File specFile, String distPath) async {
    final configuredAssetPath = Platform.environment['FROGGY_DOCS_WEB_DIR'];
    if (configuredAssetPath != null && configuredAssetPath.trim().isNotEmpty) {
      final configuredAssetDirectory = Directory(
        p.absolute(configuredAssetPath.trim()),
      );
      if (!configuredAssetDirectory.existsSync()) {
        throw FileSystemException(
          'Configured FroggyDocs web assets were not found',
          configuredAssetDirectory.path,
        );
      }
      await _copyWebAssets(configuredAssetDirectory, specFile, distPath);
      return;
    }

    final packageUri = await Isolate.resolvePackageUri(
      Uri.parse('package:froggy_docs/froggy_docs.dart'),
    );
    if (packageUri == null || packageUri.scheme != 'file') {
      throw StateError('Unable to locate FroggyDocs web assets');
    }
    final packageRoot = p.dirname(p.dirname(packageUri.toFilePath()));
    final assetDirectory = Directory(p.join(packageRoot, 'frontend', 'web'));
    if (!assetDirectory.existsSync()) {
      throw FileSystemException(
        'FroggyDocs web assets were not found',
        assetDirectory.path,
      );
    }

    await _copyWebAssets(assetDirectory, specFile, distPath);
  }

  Future<void> _copyWebAssets(
    Directory assetDirectory,
    File specFile,
    String distPath,
  ) async {
    final destination = Directory(distPath)..createSync(recursive: true);
    const assetNames = [
      'index.html',
      'app.js',
      'styles.css',
      'token_storage.js',
      'favicon.ico',
    ];
    for (final name in assetNames) {
      final source = File(p.join(assetDirectory.path, name));
      if (!source.existsSync()) {
        throw FileSystemException('Required web asset is missing', source.path);
      }
      source.copySync(p.join(destination.path, name));
    }

    final sourceImages = Directory(p.join(assetDirectory.path, 'images'));
    if (sourceImages.existsSync()) {
      await for (final entity in sourceImages.list(recursive: true)) {
        if (entity is! File) continue;
        final relativePath = p.relative(entity.path, from: assetDirectory.path);
        final target = File(p.join(destination.path, relativePath));
        target.parent.createSync(recursive: true);
        entity.copySync(target.path);
      }
    }
    specFile.copySync(p.join(destination.path, 'froggy_docs.json'));
  }

  bool _shouldIgnore(String path) {
    return path.contains('/.dart_tool/') ||
        path.contains('/frontend/') ||
        path.contains('/node_modules/') ||
        path.contains('/.git/') ||
        path.endsWith('.json') ||
        path.endsWith('.md');
  }

  void _printHelp() {
    print('''
FroggyDocs v$froggyDocsVersion

Usage:
  froggy_docs serve       Start server with live documentation
  froggy_docs watch       Watch for changes and regenerate docs
  froggy_docs build       Generate a complete deployable static site

Options:
  -p, --port <port>       Port number (default: 8080)
  -x, --proxy <url>       Proxy API requests to this URL
  -o, --output <path>     JSON specification path, or build directory
  --dist <path>           Static build directory (default: dist)
  --base-path <path>      Documentation URL base path (e.g. /docs/api/)
  --ignore <glob>         Glob pattern for paths to exclude from watching
  --project <path>        Project directory to scan
  --spec <path>           Local OpenAPI 3.0/3.1 JSON or YAML file
  --spec-url <url>        URL that returns an OpenAPI 3.0/3.1 document
  --spec-header-env <var> Environment variable containing a Name: Value header
  --spec-poll-interval <s> Seconds between remote specification reloads
  -h, --help              Show this help message

Examples:
  froggy_docs serve --project ../my-api --proxy http://localhost:3000
  froggy_docs serve --project ../my-api --base-path /docs/api/
  froggy_docs build --project ../my-api --output dist
  froggy_docs build --project ../my-api --dist public/docs/api
  froggy_docs serve --spec ../my-api/openapi.yaml
  froggy_docs serve --spec-url http://localhost:8000/openapi.json
''');
  }
}

String normalizeBasePath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == '/') return '/';
  return '/${trimmed.replaceAll(RegExp(r'^/+|/+$'), '')}/';
}

enum _InputKind { annotations, file, url }

class _InputSource {
  const _InputSource(this.kind, this.value);

  final _InputKind kind;
  final String value;
}

class _ExternalSpecContext {
  const _ExternalSpecContext({
    required this.source,
    required this.loader,
    required this.outputFile,
    required this.headers,
  });

  final _InputSource source;
  final OpenApiSpecLoader loader;
  final File outputFile;
  final Map<String, String> headers;
}
