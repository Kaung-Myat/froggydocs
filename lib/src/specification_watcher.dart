import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'openapi_spec_loader.dart';

class SpecificationWatcher {
  SpecificationWatcher({
    required OpenApiSpecLoader loader,
    required this.outputPath,
    this.debounceDuration = const Duration(milliseconds: 300),
  }) : _loader = loader;

  final OpenApiSpecLoader _loader;
  final String outputPath;
  final Duration debounceDuration;
  StreamSubscription<WatchEvent>? _subscription;
  Timer? _debounceTimer;
  Timer? _pollTimer;
  bool _reloadInProgress = false;

  Future<void> watchFile(String sourcePath) async {
    final absolutePath = p.absolute(sourcePath);
    print('Watching OpenAPI specification: $absolutePath');
    _subscription = DirectoryWatcher(p.dirname(absolutePath)).events.listen((
      event,
    ) {
      if (p.normalize(p.absolute(event.path)) != p.normalize(absolutePath)) {
        return;
      }
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounceDuration, () async {
        if (event.type == ChangeType.REMOVE) {
          _warn(
            'Specification was removed; retaining the last valid document.',
          );
          return;
        }
        await _reload(() => _loader.loadFile(absolutePath));
      });
    });
  }

  void watchUrl(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration interval = const Duration(seconds: 10),
  }) {
    print('Polling OpenAPI specification every ${interval.inSeconds}s: $uri');
    _pollTimer = Timer.periodic(interval, (_) {
      _reload(() => _loader.loadUrl(uri, headers: headers));
    });
  }

  Future<void> _reload(Future<Map<String, dynamic>> Function() load) async {
    if (_reloadInProgress) return;
    _reloadInProgress = true;
    try {
      final specification = await load();
      final changed = await _loader.write(specification, outputPath);
      if (changed) print('OpenAPI specification updated.');
    } catch (error) {
      _warn('Unable to reload specification: $error');
    } finally {
      _reloadInProgress = false;
    }
  }

  void _warn(String message) {
    stderr.writeln('Warning: $message');
  }

  Future<void> dispose() async {
    _debounceTimer?.cancel();
    _pollTimer?.cancel();
    await _subscription?.cancel();
    _loader.close();
  }
}
