import 'dart:js_interop';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;

const maxFileBytes = 25 * 1024 * 1024;

/// A modular form field component that renders either a text input or a file
/// input depending on [isFile]. File bytes are surfaced to the parent via
/// [onFileSelected]; text changes via [onTextChanged].
class FileField extends StatelessComponent {
  const FileField({
    required this.endpointKey,
    required this.fieldName,
    required this.description,
    required this.isFile,
    this.isMultiple = false,
    required this.fieldType,
    this.savedValue = '',
    required this.onTextChanged,
    required this.onFilesSelected,
    super.key,
  });

  final String endpointKey;
  final String fieldName;
  final String description;
  final bool isFile;
  final bool isMultiple;
  final String fieldType;
  final String savedValue;
  final void Function(String value) onTextChanged;
  final void Function(List<Map<String, dynamic>> files) onFilesSelected;

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'form-field',
      [
        label([Component.text('$fieldName (${isFile ? (isMultiple ? 'files' : 'file') : fieldType})')]),
        if (description.isNotEmpty) span(classes: 'field-desc', [Component.text(description)]),
        if (isFile)
          input<List<web.File>>(
            type: InputType.file,
            classes: 'form-input file-input',
            attributes: isMultiple ? const {'multiple': ''} : null,
            onChange: (files) async {
              if (files.isNotEmpty) {
                final selectedFiles = isMultiple ? files : [files.first];
                final values = <Map<String, dynamic>>[];
                for (final file in selectedFiles) {
                  if (file.size > maxFileBytes) {
                    web.window.alert(
                      '${file.name} is too large. Maximum size is '
                      '${maxFileBytes ~/ (1024 * 1024)} MB.',
                    );
                    return;
                  }
                  try {
                    final buffer = await file.arrayBuffer().toDart;
                    values.add({
                      'bytes': buffer.toDart.asUint8List(),
                      'name': file.name,
                    });
                  } catch (_) {
                    web.window.alert('Unable to read ${file.name}.');
                    return;
                  }
                }
                onFilesSelected(values);
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
    );
  }
}
