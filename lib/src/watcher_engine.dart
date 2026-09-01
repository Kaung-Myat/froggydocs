import 'dart:io';
import 'dart:async';
import 'package:watcher/watcher.dart';
import 'package:path/path.dart' as p;
import 'parser_engine.dart';
import 'froggy_config.dart';

class WatcherEngine {
  final ParserEngine _parser;
  final Map<String, Timer> _debounceTimers = {};
  final Duration _debounceDuration;
  final String? _ignorePattern;
  StreamSubscription<WatchEvent>? _subscription;

  WatcherEngine({
    String outputPath = 'frontend/web/froggy_docs.json',
    String ignorePattern = '',
    Duration debounceDuration = const Duration(milliseconds: 300),
    FroggyConfig config = const FroggyConfig(),
    String? basePath,
  }) : _parser = ParserEngine(),
       _debounceDuration = debounceDuration,
       _ignorePattern = ignorePattern.isEmpty ? null : ignorePattern {
    final runtimeExtension = Map<String, dynamic>.from(config.runtimeExtension);
    if (basePath != null) runtimeExtension['basePath'] = basePath;
    _parser.setOutputPath(outputPath);
    _parser.configureMetadata(
      title: config.title,
      version: config.version,
      description: config.description,
      servers: config.servers.map((server) => server.toOpenApi()).toList(),
      runtimeExtension: runtimeExtension,
    );
  }

  Future<void> startWatching(String directoryPath) async {
    print('🚀 Initializing FroggyDocs scan...');
    final watcher = DirectoryWatcher(directoryPath);
    _subscription = watcher.events.listen((WatchEvent event) {
      if (_shouldIgnore(event.path)) return;
      _handleFileChange(event);
    });

    await _initialScan(directoryPath);
    print('👀 Watching for changes in: ${p.absolute(directoryPath)}...\n');
  }

  Future<void> _initialScan(String directoryPath) async {
    final dir = Directory(directoryPath);
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File && !_shouldIgnore(entity.path)) {
          _parser.parseFile(entity.path, writeOutput: false);
        }
      }
      _parser.writeOutput();
    } catch (e) {
      print('⚠️  Warning during initial scan: $e');
    }
    print('✅ Initial scan complete.\n');
  }

  bool _shouldIgnore(String path) {
    final normalizedPath = path.replaceAll('\\', '/');
    if (normalizedPath.contains('/.dart_tool/') ||
        normalizedPath.contains('/frontend/') ||
        normalizedPath.contains('/node_modules/') ||
        normalizedPath.contains('/.git/') ||
        normalizedPath.endsWith('.json') ||
        normalizedPath.endsWith('.md')) {
      return true;
    }

    if (_ignorePattern != null) {
      final regexPattern = _ignorePattern
          .replaceAll('.', r'\.')
          .replaceAll('*', '.*')
          .replaceAll('?', '.');
      if (RegExp(regexPattern).hasMatch(normalizedPath)) {
        return true;
      }
    }

    return false;
  }

  void _handleFileChange(WatchEvent event) {
    final normalizedPath = p.normalize(event.path);
    _debounceTimers.remove(normalizedPath)?.cancel();

    _debounceTimers[normalizedPath] = Timer(_debounceDuration, () {
      _debounceTimers.remove(normalizedPath);
      switch (event.type) {
        case ChangeType.ADD:
        case ChangeType.MODIFY:
          _parser.parseFile(event.path);
          break;
        case ChangeType.REMOVE:
          print('🗑️  Removing documentation for: ${p.basename(event.path)}');
          _parser.removeFile(event.path);
          break;
      }
    });
  }

  Future<void> dispose() async {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    await _subscription?.cancel();
  }
}
