import 'dart:io';
import 'package:args/args.dart';
import 'package:froggy_docs/src/watcher_engine.dart';
import 'package:froggy_docs/src/web_server.dart';
import 'package:froggy_docs/src/parser_engine.dart';

class CliRunner {
  void run(List<String> arguments) async {
    final parser = ArgParser();
    parser.addCommand('watch');
    parser.addCommand('serve');
    parser.addCommand('build');
    parser.addOption(
      'port',
      abbr: 'p',
      help: 'Port for server',
      defaultsTo: '8080',
    );
    parser.addOption(
      'proxy',
      abbr: 'x',
      help: 'Proxy API requests to this URL (e.g., http://localhost:3000)',
      defaultsTo: '',
    );
    parser.addOption(
      'output',
      abbr: 'o',
      help: 'Output path for generated JSON spec (default: frontend/web/froggy_docs.json)',
      defaultsTo: 'frontend/web/froggy_docs.json',
    );
    parser.addOption(
      'ignore',
      help: 'Glob pattern for paths to exclude from watching (e.g., "**/*.g.dart")',
      defaultsTo: '',
    );

    try {
      final results = parser.parse(arguments);

      final outputPath = results['output'] as String;
      final ignorePattern = results['ignore'] as String;

      if (results.command?.name == 'watch') {
        print('🐸 FroggyDocs is watching your API project...');
        final watcher = WatcherEngine(outputPath: outputPath, ignorePattern: ignorePattern);
        watcher.startWatching(Directory.current.path);
      } else if (results.command?.name == 'serve') {
        final port = int.parse(results['port'] as String);
        final proxyUrl = results['proxy'] as String;
        print('🐸 Starting FroggyDocs server with live reload...');
        if (proxyUrl.isNotEmpty) {
          print('🔄 Proxy enabled: API requests will be forwarded to $proxyUrl');
        }

        await startServer(port: port, proxyUrl: proxyUrl);
        final watcher = WatcherEngine(outputPath: outputPath, ignorePattern: ignorePattern);
        watcher.startWatching(Directory.current.path);
      } else if (results.command?.name == 'build') {
        print('🐸 Building static FroggyDocs site...');
        final parser = ParserEngine();
        parser.setOutputPath(outputPath);
        _buildStaticSite(parser, Directory.current.path);
        print('✅ Build complete. Output: $outputPath');
      } else {
        _printHelp();
      }
    } catch (e) {
      print('Error: ${e.toString()}');
      exit(1);
    }
  }

  void _buildStaticSite(ParserEngine parser, String directoryPath) {
    final dir = Directory(directoryPath);
    try {
      dir.listSync(recursive: true).forEach((entity) {
        if (entity is File) {
          final normalizedPath = entity.path.replaceAll('\\', '/');
          if (!_shouldIgnore(normalizedPath)) {
            parser.parseFile(entity.path);
          }
        }
      });
    } catch (e) {
      print('⚠️  Warning during build: $e');
    }
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
🐸 FroggyDocs v1.0.0

Usage:
  froggy_docs serve       Start server with live documentation
  froggy_docs watch       Watch for changes and regenerate docs
  froggy_docs build       Generate static documentation without starting server

Options:
  -p, --port <port>       Port number (default: 8080)
  -x, --proxy <url>       Proxy API requests to this URL
  -o, --output <path>     Output path for generated JSON spec
                          (default: frontend/web/froggy_docs.json)
  --ignore <glob>         Glob pattern for paths to exclude from watching
                          (e.g., "**/*.g.dart")
  -h, --help              Show this help message

Examples:
  froggy_docs serve --port 3000
  froggy_docs serve --output docs/api.json
  froggy_docs build --output docs/froggy_docs.json
  froggy_docs watch --ignore "**/*.g.dart"
''');
  }
}
