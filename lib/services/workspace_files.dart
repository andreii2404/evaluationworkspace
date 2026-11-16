import 'cloud_repository.dart';

const workspaceFileTypes = <String, String>{};

Future<QuestionnaireFile?> pickWorkspaceFile() async =>
    throw const FormatException(
      'Open In Cantiere in a browser to upload files.',
    );

void downloadWorkspaceCsv(String name, String content) =>
    throw const FormatException(
      'Open In Cantiere in a browser to export results.',
    );
