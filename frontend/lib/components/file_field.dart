import 'dart:js_interop';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;

/// A modular form field component that renders either a text input or a file
/// input depending on [isFile]. File bytes are surfaced to the parent via
/// [onFileSelected]; text changes via [onTextChanged].
class FileField extends StatelessComponent {
  const FileField({
    required this.endpointKey,
    required this.fieldName,
    required this.description,
    required this.isFile,
    required this.fieldType,
    this.savedValue = '',
    required this.onTextChanged,
    required this.onFileSelected,
    super.key,
  });

  final String endpointKey;
  final String fieldName;
  final String description;
  final bool isFile;
  final String fieldType;
  final String savedValue;
  final void Function(String value) onTextChanged;
  final void Function(List<int> bytes, String name) onFileSelected;

  @override
  Component build(BuildContext context) {
    return div(
      [
        label([Component.text('$fieldName (${isFile ? 'file' : fieldType})')]),
        if (description.isNotEmpty)
          span([Component.text(description)], classes: 'field-desc'),
        if (isFile)
          input<List<web.File>>(
            type: InputType.file,
            classes: 'form-input file-input',
            onChange: (files) {
              if (files.isNotEmpty) {
                final file = files.first;
                final fileName = file.name;
                final reader = web.FileReader();
                reader.addEventListener(
                  'load',
                  ((JSAny? _) {
                    final result = reader.result;
                    if (result != null) {
                      onFileSelected(
                        (result as JSArrayBuffer).toDart.asUint8List(),
                        fileName,
                      );
                    }
                  }).toJS,
                );
                reader.readAsArrayBuffer(file);
              }
            },
          )
        else
          input<String>(
            type: InputType.text,
            classes: 'form-input',
            value: savedValue,
            onInput: onTextChanged,
          ),
      ],
      classes: 'form-field',
    );
  }
}
