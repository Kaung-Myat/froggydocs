import 'dart:io';
import 'dart:async';
import 'package:args/args.dart';
import 'package:froggy_docs/src/watcher_engine.dart';
import 'package:froggy_docs/src/web_server.dart';

void main(List<String> arguments) async {
  final parser = ArgParser();
  parser.addCommand('watch');
  parser.addCommand('serve');
  parser.addOption(
    'port',
    abbr: 'p',
    help: 'Port for server',
    defaultsTo: '8080',
  );

  try {
    final results = parser.parse(arguments);

    if (results.command?.name == 'watch') {
      print('🐸 FroggyDocs is watching your API project...');
      final watcher = WatcherEngine();
      watcher.startWatching(Directory.current.path);
    } else if (results.command?.name == 'serve') {
      final port = int.parse(results['port'] as String);
      print('🐸 Starting FroggyDocs server with live reload...');

      // Start server and watcher
      await startServer(port: port);
      final watcher = WatcherEngine();
      watcher.startWatching(Directory.current.path);
    }
  } catch (e) {
    print('Error: ${e.toString()}');
    exit(1);
  }
}
