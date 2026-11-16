import 'dart:async';

import 'package:web/web.dart' as web;
import 'dart:js_interop';

import 'cloud_repository.dart';

const workspaceFileTypes = {
  'pdf': 'application/pdf',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'csv': 'text/csv',
  'txt': 'text/plain',
  'md': 'text/markdown',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
  'zip': 'application/zip',
};

Future<QuestionnaireFile?> pickWorkspaceFile() async {
  final picker = web.HTMLInputElement()
    ..type = 'file'
    ..accept = workspaceFileTypes.keys.map((ext) => '.$ext').join(',')
    ..style.display = 'none';
  final picked = Completer<web.File?>();
  picker.onchange = ((web.Event _) => picked.complete(
    picker.files?.item(0),
  )).toJS;
  picker.oncancel = ((web.Event _) => picked.complete(null)).toJS;
  web.document.body?.append(picker);
  try {
    picker.click();
    final file = await picked.future;
    if (file == null) return null;
    if (file.size > 10 * 1024 * 1024) {
      throw const FormatException('Choose a file of 10 MB or less.');
    }
    final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
    return (name: file.name, bytes: bytes);
  } finally {
    picker.remove();
  }
}

void downloadWorkspaceCsv(String name, String content) {
  final blob = web.Blob(
    [content.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 3), () => web.URL.revokeObjectURL(url));
}
