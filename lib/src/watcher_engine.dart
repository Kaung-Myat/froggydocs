import 'dart:io';
import 'dart:async';
import 'package:watcher/watcher.dart';
import 'package:path/path.dart' as p;
import 'parser_engine.dart';

class WatcherEngine {
  final ParserEngine _parser;
  Timer? _debounceTimer;
  final Duration _debounceDuration;
  final String? _ignorePattern;

  WatcherEngine({
    String outputPath = 'frontend/web/froggy_docs.json',
    String ignorePattern = '',
    Duration debounceDuration = const Duration(milliseconds: 300),
  })  : _parser = ParserEngine(),
        _debounceDuration = debounceDuration,
        _ignorePattern = ignorePattern.isEmpty ? null : ignorePattern {
    _parser.setOutputPath(outputPath);
  }

  void startWatching(String directoryPath) {
    print('🚀 Initializing FroggyDocs scan...');
    _initialScan(directoryPath);

    final watcher = DirectoryWatcher(directoryPath);
    print('👀 Watching for changes in: ${p.absolute(directoryPath)}...\n');

    watcher.events.listen((WatchEvent event) {
      if (_shouldIgnore(event.path)) return;
      _handleFileChange(event);
    });
  }

  void _initialScan(String directoryPath) {
    final dir = Directory(directoryPath);
    try {
      dir.listSync(recursive: true).forEach((entity) {
        if (entity is File && !_shouldIgnore(entity.path)) {
          _parser.parseFile(entity.path);
        }
      });
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
    _debounceTimer?.cancel();

    _debounceTimer = Timer(_debounceDuration, () {
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
}
