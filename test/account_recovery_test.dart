import 'dart:convert';

import 'package:evaluationworkspace/main.dart';
import 'package:evaluationworkspace/screens/auth_screen.dart';
import 'package:evaluationworkspace/services/cloud_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _userId = '5ca3a9c6-8cb7-45ac-8103-04ddf4d25f1b';

http.Response _json(http.Request request, Object body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json'},
      request: request,
    );

Future<SupabaseClient> _signedInClient(MockClient httpClient) async {
  final client = SupabaseClient(
    'https://example.test',
    'test-key',
    httpClient: httpClient,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'sub': _userId,
            'exp':
                DateTime.now()
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch ~/
                1000,
          }),
        ),
      )
      .replaceAll('=', '');
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.fixture',
      'refresh_token': 'fixture',
      'token_type': 'bearer',
      'user': {
        'id': _userId,
        'aud': 'authenticated',
        'email': 'member@example.test',
      },
    }),
  );
  return client;
}

Future<SupabaseClient> _authClient(
  WidgetTester tester, [
  MockClient? httpClient,
]) async => (await tester.runAsync(
  () async => SupabaseClient(
    'https://example.test',
    'test-key',
    httpClient: httpClient,
    authOptions: const AuthClientOptions(
      autoRefreshToken: false,
      authFlowType: AuthFlowType.implicit,
    ),
  ),
))!;

void main() {
  testWidgets('an expired email link explains how to recover', (tester) async {
    final client = await _authClient(tester);
    await tester.pumpWidget(
      EvalinkApp(client: client, authReturn: true, authLinkExpired: true),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('This email link has expired'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
  });

  testWidgets('a restricted email reports the delivery failure', (
    tester,
  ) async {
    final client = await _authClient(
      tester,
      MockClient((request) async {
        expect(request.url.path, '/auth/v1/recover');
        return _json(request, {
          'error_code': 'email_address_not_authorized',
          'msg': 'Email address not authorized',
        }, 403);
      }),
    );
    await tester.pumpWidget(MaterialApp(home: AuthScreen(client: client)));
    await tester.pumpAndSettle();
    final forgot = find.text('Forgot password?');
    await tester.ensureVisible(forgot);
    await tester.tap(forgot);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'member@example.test');
    await tester.tap(
      find.text(
        const bool.fromEnvironment('AUTH_EMAIL_CODES')
            ? 'Send reset code'
            : 'Send reset link',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Email verification is unavailable for this address.'),
      findsOneWidget,
    );
    expect(find.text('Check your email'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
  });

  if (const bool.fromEnvironment('AUTH_EMAIL_CODES')) {
    testWidgets('an eight-digit reset code reaches Auth intact', (
      tester,
    ) async {
      final requests = <http.Request>[];
      final client = await _authClient(
        tester,
        MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/auth/v1/recover') {
            return _json(request, {});
          }
          expect(request.url.path, '/auth/v1/verify');
          return _json(request, {
            'error_code': 'otp_expired',
            'msg': 'Expired',
          }, 403);
        }),
      );
      await tester.pumpWidget(MaterialApp(home: AuthScreen(client: client)));
      await tester.pumpAndSettle();
      final forgot = find.text('Forgot password?');
      await tester.ensureVisible(forgot);
      await tester.tap(forgot);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'member@example.test');
      await tester.tap(find.text('Send reset code'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '0123 4567');
      await tester.tap(find.text('Verify code'));
      await tester.pumpAndSettle();
      expect(requests.length, 2);
      expect(jsonDecode(requests.last.body)['token'], '01234567');
      expect(jsonDecode(requests.last.body)['type'], 'recovery');
      expect(
        find.textContaining('This code is incorrect or expired'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    });
  }

  for (final (name, body, status) in [
    ('a deleted profile', [], 200),
    ('a rejected JWT', {'code': 'PGRST301', 'message': 'JWT expired'}, 401),
  ]) {
    testWidgets('$name returns to sign-in and clears the session', (
      tester,
    ) async {
      var logoutRequests = 0;
      final client = (await tester.runAsync(
        () => _signedInClient(
          MockClient((request) async {
            if (request.url.path.endsWith('/profiles')) {
              return _json(request, body, status);
            }
            expect(request.url.path, '/auth/v1/logout');
            logoutRequests++;
            return _json(request, {
              'code': 'session_not_found',
              'msg': 'Session not found',
            }, 403);
          }),
        ),
      ))!;

      await tester.pumpWidget(EvalinkApp(client: client, authReturn: true));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text(workspaceSessionEndedMessage), findsOneWidget);
      expect(client.auth.currentSession, isNull);
      expect(logoutRequests, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    });
  }

  testWidgets(
    'a temporary profile failure can be retried without signing out',
    (tester) async {
      var profileRequests = 0;
      final client = (await tester.runAsync(
        () => _signedInClient(
          MockClient((request) async {
            expect(request.url.path, '/rest/v1/profiles');
            if (++profileRequests == 1) {
              return _json(request, {
                'code': 'PGRST000',
                'message': 'Unavailable',
              }, 500);
            }
            return _json(request, [
              {
                'id': _userId,
                'display_name': 'Avery Chen',
                'onboarding_completed': false,
              },
            ]);
          }),
        ),
      ))!;

      await tester.pumpWidget(EvalinkApp(client: client, authReturn: true));
      await tester.pumpAndSettle();
      expect(find.text('Back to sign in'), findsOneWidget);
      expect(client.auth.currentUser?.id, _userId);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to In Cantiere'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Set up your profile'), findsOneWidget);
      expect(client.auth.currentUser?.id, _userId);
      expect(profileRequests, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    },
  );
}
