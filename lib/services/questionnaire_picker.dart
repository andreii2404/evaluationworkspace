import 'cloud_repository.dart';

Future<QuestionnaireFile?> pickQuestionnaireFile({
  bool allowWord = false,
}) async =>
    throw UnsupportedError('File upload is available in the web workspace.');

void downloadQuestionnaireTemplate(String asset) => throw UnsupportedError(
  'Template downloads are available in the web workspace.',
);
