import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'screens/auth_screen.dart';
import 'screens/account_security_screen.dart';
import 'screens/cloud_workspace.dart';
import 'screens/landing_screen.dart';
import 'services/cloud_repository.dart';
import 'widgets/cantiere_wordmark.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  // Read the incoming URI before Supabase exchanges the code and cleans it.
  final parameters = kIsWeb
      ? _authReturnParameters(Uri.base)
      : const <String, String>{};
  final authReturn = _isAuthReturn(parameters);
  SupabaseClient? client;
  if (url.isNotEmpty && key.isNotEmpty) {
    await Supabase.initialize(
      url: url,
      publishableKey: key,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    client = Supabase.instance.client;
  }
  runApp(
    EvalinkApp(
      client: client,
      authReturn: authReturn,
      authLinkExpired: parameters['error_code'] == 'otp_expired',
    ),
  );
}

Map<String, String> _authReturnParameters(Uri uri) => {
  ...uri.queryParameters,
  if (!uri.fragment.startsWith('/')) ...Uri.splitQueryString(uri.fragment),
};

bool _isAuthReturn(Map<String, String> parameters) {
  const keys = {
    'code',
    'access_token',
    'error',
    'error_code',
    'error_description',
  };
  return parameters.keys.any(keys.contains);
}

class EvalinkApp extends StatelessWidget {
  const EvalinkApp({
    super.key,
    this.client,
    this.authReturn = false,
    this.authLinkExpired = false,
  });
  final SupabaseClient? client;
  final bool authReturn;
  final bool authLinkExpired;

  @override
  Widget build(BuildContext context) {
    final opensWorkspace = client != null && authReturn;
    Widget workspace(BuildContext context) => _WorkspaceGate(
      client: client,
      authReturnFailed: opensWorkspace && client?.auth.currentUser == null,
      authLinkExpired: opensWorkspace && authLinkExpired,
    );
    return MaterialApp(
      title: cantiereName,
      debugShowCheckedModeBanner: false,
      theme: evalinkTheme(),
      initialRoute: opensWorkspace ? '/workspace' : null,
      onGenerateInitialRoutes: opensWorkspace
          ? (route) => [
              MaterialPageRoute<void>(
                settings: RouteSettings(name: route),
                builder: workspace,
              ),
            ]
          : null,
      routes: {
        '/': (_) => const LandingScreen(),
        '/login': (_) => _WorkspaceGate(client: client),
        '/signup': (_) =>
            _WorkspaceGate(client: client, initiallyRegister: true),
        '/workspace': workspace,
      },
    );
  }
}

class _WorkspaceGate extends StatefulWidget {
  const _WorkspaceGate({
    required this.client,
    this.authReturnFailed = false,
    this.authLinkExpired = false,
    this.initiallyRegister = false,
  });
  final SupabaseClient? client;
  final bool authReturnFailed;
  final bool authLinkExpired;
  final bool initiallyRegister;

  @override
  State<_WorkspaceGate> createState() => _WorkspaceGateState();
}

class _WorkspaceGateState extends State<_WorkspaceGate> {
  bool _recovery = false;
  AuthState? _handledAuthEvent;

  @override
  Widget build(BuildContext context) {
    final supabase = widget.client;
    if (supabase == null) {
      return Scaffold(
        appBar: AppBar(title: const CantiereWordmark(dark: false)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Account access is temporarily unavailable.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      Navigator.popUntil(context, ModalRoute.withName('/')),
                  child: const Text('Back to home'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final user = supabase.auth.currentUser;
        final event = snapshot.data;
        if (event != null && !identical(event, _handledAuthEvent)) {
          _handledAuthEvent = event;
          if (event.event == AuthChangeEvent.passwordRecovery && user != null) {
            _recovery = true;
          } else if (event.event == AuthChangeEvent.signedOut) {
            _recovery = false;
          }
        }
        final initialAuthReturn =
            event == null || event.event == AuthChangeEvent.initialSession;
        return user == null
            ? AuthScreen(
                client: supabase,
                initiallyRegister: widget.initiallyRegister,
                onRecovery: (active) => _recovery = active,
                sessionEnded:
                    workspaceSessionEnded(snapshot.error) ||
                    snapshot.data?.signOutReason ==
                        SignOutReason.sessionExpired ||
                    snapshot.data?.signOutReason ==
                        SignOutReason.sessionMissing,
                authReturnFailed:
                    snapshot.hasError ||
                    (widget.authReturnFailed && initialAuthReturn),
                authLinkExpired: widget.authLinkExpired && initialAuthReturn,
              )
            : AccountSecurityGate(
                key: ValueKey(user.id),
                client: supabase,
                recovery: _recovery,
                finishRecovery: () {
                  setState(() => _recovery = false);
                },
                child: CloudWorkspace(client: supabase, userId: user.id),
              );
      },
    );
  }
}
