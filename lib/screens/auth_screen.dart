import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_theme.dart';
import '../services/cloud_repository.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.client,
    this.authReturnFailed = false,
  });
  final SupabaseClient client;
  final bool authReturnFailed;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _working = false;
  bool _googleWorking = false;
  late String? _message = widget.authReturnFailed
      ? 'Sign-in didn’t finish. Please try again.'
      : null;
  late bool _error = widget.authReturnFailed;

  bool get _busy => _working || _googleWorking;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _appRedirect() {
    final base = Uri.base;
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: base.path,
    ).toString();
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _error = true;
      _message = message;
    });
  }

  Future<void> _signInWithGoogle() async {
    if (_busy) return;
    setState(() {
      _googleWorking = true;
      _message = null;
    });
    try {
      // The public Auth settings endpoint reflects provider changes immediately.
      const url = String.fromEnvironment('SUPABASE_URL');
      const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
      final settings = await http
          .get(
            Uri.parse(
              '${url.replaceFirst(RegExp(r'/$'), '')}/auth/v1/settings',
            ),
            headers: {'apikey': key},
          )
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (settings.statusCode != 200) {
        _showError('Couldn’t reach sign-in. Please try again.');
        return;
      }
      final providers =
          (jsonDecode(settings.body) as Map<String, dynamic>)['external'];
      if (providers is! Map<String, dynamic> || providers['google'] != true) {
        _showError('Google sign-in is unavailable for this workspace.');
        return;
      }
      final launched = await widget.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _appRedirect(),
        queryParams: const {'prompt': 'select_account'},
      );
      if (!launched) {
        _showError('Couldn’t open Google sign-in. Please try again.');
      }
    } catch (_) {
      _showError('Couldn’t start Google sign-in. Please try again.');
    } finally {
      if (mounted) setState(() => _googleWorking = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      if (_register) {
        final response = await widget.client.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'display_name': _name.text.trim()},
          emailRedirectTo: _appRedirect(),
        );
        if (mounted && response.session == null) {
          setState(() {
            _error = false;
            _message = 'Check your email to confirm your account.';
          });
        }
      } else {
        await widget.client.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } catch (error) {
      _showError(
        error is AuthException && error.code == 'invalid_credentials'
            ? 'Check your EvaLink email and password. New here? Create an account.'
            : workspaceError(error),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const EvalinkMark()),
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8F5FF), canvas],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 410),
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _register ? 'Create your account' : 'Welcome back',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _signInWithGoogle,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1F1F1F),
                        side: const BorderSide(color: Color(0xFF747775)),
                      ),
                      icon: Image.asset(
                        'assets/auth/google-g.png',
                        width: 18,
                        height: 18,
                        excludeFromSemantics: true,
                      ),
                      label: Text(
                        _googleWorking
                            ? 'Opening Google…'
                            : 'Continue with Google',
                      ),
                    ),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _message!,
                            style: TextStyle(
                              color: _error
                                  ? Theme.of(context).colorScheme.error
                                  : ink,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('or use email'),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (_register) ...[
                      TextFormField(
                        controller: _name,
                        enabled: !_busy,
                        maxLength: 80,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                        ),
                        validator: (value) =>
                            value!.trim().isEmpty ? 'Enter your name' : null,
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) => !value!.trim().contains('@')
                          ? 'Enter an email address'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: true,
                      autofillHints: [
                        _register
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: const InputDecoration(labelText: 'Password'),
                      onFieldSubmitted: (_) => _submit(),
                      validator: (value) =>
                          value!.isEmpty || (_register && value.length < 8)
                          ? 'Use at least 8 characters'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(
                        _working
                            ? 'Please wait…'
                            : _register
                            ? 'Create account'
                            : 'Sign in',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _register = !_register;
                              _message = null;
                            }),
                      child: Text(
                        _register
                            ? 'Already have an account? Sign in'
                            : 'Create an account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
