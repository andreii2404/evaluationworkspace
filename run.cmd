@echo off
setlocal
cd /d "%~dp0" || exit /b 1

if not exist ".dart_tool\evalink-hosted.json" (
  echo Missing .dart_tool\evalink-hosted.json. See the hosted setup in README.md.
  exit /b 1
)

call flutter run -d chrome --web-hostname=127.0.0.1 --web-port=8080 --dart-define-from-file=.dart_tool/evalink-hosted.json
exit /b %errorlevel%
