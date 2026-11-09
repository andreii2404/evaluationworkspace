import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'screens/auth_screen.dart';
import 'screens/cloud_workspace.dart';
import 'screens/landing_screen.dart';
import 'screens/workspace_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  // Read the incoming URI before Supabase exchanges the code and cleans it.
  final authReturn = kIsWeb && _isAuthReturn(Uri.base);
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
  runApp(EvalinkApp(client: client, authReturn: authReturn));
}

bool _isAuthReturn(Uri uri) {
  const keys = {
    'code',
    'access_token',
    'error',
    'error_code',
    'error_description',
  };
  return uri.queryParameters.keys.any(keys.contains) ||
      (!uri.fragment.startsWith('/') &&
          Uri.splitQueryString(uri.fragment).keys.any(keys.contains));
}

class EvalinkApp extends StatelessWidget {
  const EvalinkApp({super.key, this.client, this.authReturn = false});
  final SupabaseClient? client;
  final bool authReturn;

  @override
  Widget build(BuildContext context) {
    final opensWorkspace = client != null && authReturn;
    Widget workspace(BuildContext context) => _WorkspaceGate(
      client: client,
      authReturnFailed: opensWorkspace && client?.auth.currentUser == null,
    );
    return MaterialApp(
      title: 'Evalink',
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
        '/': (_) => LandingScreen(connected: client != null),
        '/demo': (_) => const WorkspaceScreen(),
        '/workspace': workspace,
      },
    );
  }
}

class _WorkspaceGate extends StatelessWidget {
  const _WorkspaceGate({required this.client, required this.authReturnFailed});
  final SupabaseClient? client;
  final bool authReturnFailed;

  @override
  Widget build(BuildContext context) {
    final supabase = client;
    if (supabase == null) {
      return Scaffold(
        appBar: AppBar(title: const EvalinkMark()),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Accounts are unavailable in this preview.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, '/demo'),
                  child: const Text('Open demo'),
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
        return user == null
            ? AuthScreen(
                client: supabase,
                authReturnFailed:
                    snapshot.hasError ||
                    (authReturnFailed &&
                        (snapshot.data == null ||
                            snapshot.data?.event ==
                                AuthChangeEvent.initialSession)),
              )
            : CloudWorkspace(
                key: ValueKey(user.id),
                client: supabase,
                userId: user.id,
              );
      },
    );
  }
}
