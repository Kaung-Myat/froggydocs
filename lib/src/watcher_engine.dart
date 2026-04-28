import 'dart:io';
import 'package:watcher/watcher.dart';
import 'package:path/path.dart' as p;
import 'parser_engine.dart';

class WatcherEngine {
  final ParserEngine _parser = ParserEngine();

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
      print('⚠️ Warning during initial scan: $e');
    }
    print('✅ Initial scan complete.\n');
  }

  bool _shouldIgnore(String path) {
    final normalizedPath = path.replaceAll('\\', '/');
    return normalizedPath.contains('/.dart_tool/') ||
        normalizedPath.contains('/frontend/') ||
        normalizedPath.contains('/node_modules/') ||
        normalizedPath.contains('/.git/') ||
        normalizedPath.endsWith('.json') ||
        normalizedPath.endsWith('.md');
  }

  void _handleFileChange(WatchEvent event) {
    switch (event.type) {
      case ChangeType.ADD:
      case ChangeType.MODIFY:
        _parser.parseFile(event.path);
        break;
      case ChangeType.REMOVE:
        print('🗑️ Removing documentation for: ${p.basename(event.path)}');
        _parser.removeFile(event.path);
        break;
    }
  }
}
