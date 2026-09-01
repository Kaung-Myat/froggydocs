import 'package:froggy_docs/src/cli_runner.dart';

Future<void> main(List<String> arguments) async {
  final runner = CliRunner();
  await runner.run(arguments);
}
