import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:froggy_docs/src/froggy_config.dart';
import 'package:froggy_docs/src/parser_engine.dart';
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
      );

    try {
      final results = parser.parse(arguments);
      final projectPath = results['project'] as String;
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

      if (results.command?.name == 'watch') {
        print('🐸 FroggyDocs is watching your API project...');
        await WatcherEngine(
          outputPath: outputPath,
          ignorePattern: ignorePattern,
          config: config,
          basePath: basePath,
        ).startWatching(Directory.current.path);
      } else if (results.command?.name == 'serve') {
        final port = results.wasParsed('port')
            ? int.parse(results['port'] as String)
            : config.port;
        final proxyArgument = results['proxy'] as String;
        final proxyUrl = proxyArgument.isNotEmpty
            ? proxyArgument
            : config.proxyUrl;

        await _generateSpecification(
          config,
          outputPath,
          Directory.current.path,
          basePath: basePath,
        );
        print('🐸 Starting FroggyDocs server with live reload...');
        if (proxyUrl.isNotEmpty) {
          print(
            '🔄 Proxy enabled: API requests will be forwarded to $proxyUrl',
          );
        }
        await startServer(port: port, proxyUrl: proxyUrl, basePath: basePath);
        await WatcherEngine(
          outputPath: outputPath,
          ignorePattern: ignorePattern,
          config: config,
          basePath: basePath,
        ).startWatching(Directory.current.path);
      } else if (results.command?.name == 'build') {
        print('🐸 Building deployable FroggyDocs site...');
        final specFile = await _generateSpecification(
          config,
          outputPath,
          Directory.current.path,
          basePath: basePath,
          excludedDirectory: distPath,
        );
        await _exportStaticSite(specFile, distPath);
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
  -h, --help              Show this help message

Examples:
  froggy_docs serve --project ../my-api --proxy http://localhost:3000
  froggy_docs serve --project ../my-api --base-path /docs/api/
  froggy_docs build --project ../my-api --output dist
  froggy_docs build --project ../my-api --dist public/docs/api
''');
  }
}

String normalizeBasePath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == '/') return '/';
  return '/${trimmed.replaceAll(RegExp(r'^/+|/+$'), '')}/';
}
