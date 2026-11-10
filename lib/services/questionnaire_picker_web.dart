import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'cloud_repository.dart';

Future<QuestionnaireFile?> pickQuestionnaireFile({
  bool allowWord = false,
}) async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = allowWord ? '.pdf,.docx' : '.pdf,application/pdf'
    ..style.display = 'none';
  final selection = Completer<web.File?>();
  input.onchange = ((web.Event _) {
    selection.complete(input.files?.item(0));
  }).toJS;
  input.oncancel = ((web.Event _) {
    selection.complete(null);
  }).toJS;
  web.document.body?.appendChild(input);
  try {
    input.click();
    final file = await selection.future;
    if (file == null) return null;
    if (file.size > 5 * 1024 * 1024) {
      throw const FormatException('Choose a file up to 5 MB.');
    }
    if (file.name.length > 180) {
      throw const FormatException('Shorten the file name and try again.');
    }
    final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
    final name = file.name.toLowerCase();
    final pdf =
        name.endsWith('.pdf') &&
        bytes.length >= 5 &&
        String.fromCharCodes(bytes, 0, 5) == '%PDF-';
    final word =
        allowWord &&
        name.endsWith('.docx') &&
        bytes.length >= 4 &&
        bytes[0] == 80 &&
        bytes[1] == 75 &&
        bytes[2] == 3 &&
        bytes[3] == 4;
    if (!pdf && !word) {
      throw FormatException(
        allowWord
            ? 'Choose a valid PDF or Word (.docx) file.'
            : 'Choose a valid PDF file.',
      );
    }
    return (name: file.name, bytes: bytes);
  } finally {
    input.remove();
  }
}

void downloadQuestionnaireTemplate(String asset) {
  final link = web.HTMLAnchorElement()
    ..href = Uri.parse(web.document.baseURI).resolve('assets/$asset').toString()
    ..download = asset.split('/').last;
  web.document.body?.appendChild(link);
  link.click();
  link.remove();
}
