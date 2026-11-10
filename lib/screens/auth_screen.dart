import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cloud_repository.dart';
import '../widgets/app_notice.dart';
import '../widgets/cantiere_wordmark.dart';
import '../widgets/liquid_glass.dart';

const _night = Color(0xFF001233);
const _primary = Color(0xFF0466C8);
const _paleBlue = Color(0xFFC7E0FF);
const _bright = Color(0xFFF5FAFF);
const _border = Color(0x8DA9C5E5);
const _warning = Color(0xFFFFC8CC);

enum _SignUpStep { details, password, confirmation }

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.client,
    this.authReturnFailed = false,
    this.initiallyRegister = false,
  });

  final SupabaseClient client;
  final bool authReturnFailed;
  final bool initiallyRegister;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmationFocus = FocusNode();
  late final _googleAvailable = _readGoogleAvailability();
  late bool _register = widget.initiallyRegister;
  var _step = _SignUpStep.details;
  bool _passwordVisible = false;
  bool _working = false;
  bool _googleWorking = false;
  bool _checkEmail = false;
  late String? _error = widget.authReturnFailed
      ? 'Sign-in didn’t finish. Please try again.'
      : null;

  bool get _busy => _working || _googleWorking;
  bool get _details => _step == _SignUpStep.details;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmationFocus.dispose();
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

  Future<bool> _readGoogleAvailability() async {
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    if (url.isEmpty || key.isEmpty) return false;
    try {
      final response = await http
          .get(
            Uri.parse(
              '${url.replaceFirst(RegExp(r'/$'), '')}/auth/v1/settings',
            ),
            headers: {'apikey': key},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return false;
      final providers =
          (jsonDecode(response.body) as Map<String, dynamic>)['external'];
      return providers is Map<String, dynamic> && providers['google'] == true;
    } catch (_) {
      return false;
    }
  }

  void _showError(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _signInWithGoogle() async {
    if (_busy) return;
    setState(() {
      _googleWorking = true;
      _error = null;
    });
    try {
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

  void _changeStep(_SignUpStep step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = step;
      _passwordVisible = false;
      _error = null;
    });
    final target = switch (step) {
      _SignUpStep.details => _emailFocus,
      _SignUpStep.password => _passwordFocus,
      _SignUpStep.confirmation => _confirmationFocus,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _step == step && target.context != null) {
        target.requestFocus();
      }
    });
  }

  void _switchMode() {
    FocusScope.of(context).unfocus();
    _password.clear();
    _confirmation.clear();
    setState(() {
      _register = !_register;
      _step = _SignUpStep.details;
      _checkEmail = false;
      _passwordVisible = false;
      _error = null;
    });
  }

  Future<void> _continue() async {
    if (_busy || _form.currentState?.validate() != true) return;
    if (_register && _step != _SignUpStep.confirmation) {
      if (_step == _SignUpStep.password) _confirmation.clear();
      _changeStep(_details ? _SignUpStep.password : _SignUpStep.confirmation);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _working = true;
      _passwordVisible = false;
      _error = null;
    });
    try {
      if (_register) {
        final response = await widget.client.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'display_name': _name.text.trim()},
          emailRedirectTo: _appRedirect(),
        );
        if (!mounted) return;
        TextInput.finishAutofillContext(shouldSave: true);
        if (response.session == null) {
          _password.clear();
          _confirmation.clear();
          setState(() => _checkEmail = true);
        }
      } else {
        await widget.client.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        if (mounted) TextInput.finishAutofillContext(shouldSave: true);
      }
    } catch (error) {
      _showError(
        error is AuthException && error.code == 'invalid_credentials'
            ? 'Check your email and password and try again.'
            : workspaceError(error),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _home() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed('/');
    }
  }

  String get _title {
    if (_checkEmail) return 'Check your email';
    if (!_register) return 'Welcome back';
    return switch (_step) {
      _SignUpStep.details => 'Create an account',
      _SignUpStep.password => 'Create a password',
      _SignUpStep.confirmation => 'Confirm your password',
    };
  }

  String get _description {
    if (_checkEmail) {
      return 'Open the confirmation link for ${_email.text.trim()}.';
    }
    if (!_register) return 'Log in to your $cantiereName workspace.';
    return switch (_step) {
      _SignUpStep.details => 'Enter your name and email to get started.',
      _SignUpStep.password => 'Use at least 8 characters.',
      _SignUpStep.confirmation => 'Enter the same password again.',
    };
  }

  InputDecoration _field(String label, IconData icon, {Widget? trailing}) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 19),
        suffixIcon: trailing,
      );

  Widget _nameField() => TextFormField(
    controller: _name,
    enabled: !_busy,
    maxLength: 80,
    textInputAction: TextInputAction.next,
    autofillHints: const [AutofillHints.name],
    decoration: _field('Display name', Icons.person_outline_rounded),
    buildCounter:
        (context, {required currentLength, required isFocused, maxLength}) =>
            null,
    validator: (value) => value!.trim().isEmpty ? 'Enter your name.' : null,
    onFieldSubmitted: (_) => _emailFocus.requestFocus(),
  );

  Widget _emailField() => TextFormField(
    controller: _email,
    focusNode: _emailFocus,
    enabled: !_busy,
    keyboardType: TextInputType.emailAddress,
    textInputAction: _register ? TextInputAction.done : TextInputAction.next,
    autofillHints: const [AutofillHints.email],
    decoration: _field('Email', Icons.mail_outline_rounded),
    validator: (value) =>
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value!.trim())
        ? 'Enter a valid email address.'
        : null,
    onFieldSubmitted: (_) {
      if (_register) {
        _continue();
      } else {
        _passwordFocus.requestFocus();
      }
    },
  );

  Widget _passwordField({bool confirmation = false}) => TextFormField(
    controller: confirmation ? _confirmation : _password,
    focusNode: confirmation ? _confirmationFocus : _passwordFocus,
    enabled: !_busy,
    obscureText: !_passwordVisible,
    autocorrect: false,
    enableSuggestions: false,
    textInputAction: TextInputAction.done,
    autofillHints: confirmation
        ? null
        : [_register ? AutofillHints.newPassword : AutofillHints.password],
    decoration: _field(
      confirmation ? 'Confirm password' : 'Password',
      Icons.lock_outline_rounded,
      trailing: IconButton(
        tooltip: _passwordVisible ? 'Hide password' : 'Show password',
        onPressed: _busy
            ? null
            : () => setState(() => _passwordVisible = !_passwordVisible),
        icon: Icon(
          _passwordVisible
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: 19,
        ),
      ),
    ),
    validator: (value) {
      if (value == null || value.isEmpty) {
        return confirmation ? 'Confirm your password.' : 'Enter your password.';
      }
      if (confirmation && value != _password.text) {
        return 'Passwords don’t match.';
      }
      if (_register && !confirmation && value.length < 8) {
        return 'Use at least 8 characters.';
      }
      return null;
    },
    onFieldSubmitted: (_) => _continue(),
  );

  Widget _google() => FutureBuilder<bool>(
    future: _googleAvailable,
    builder: (context, snapshot) => snapshot.data == true
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _signInWithGoogle,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _bright,
                  backgroundColor: const Color(0x302F639D),
                  side: const BorderSide(color: _border),
                  shape: const StadiumBorder(),
                ),
                icon: Image.asset(
                  'assets/auth/google-g.png',
                  width: 18,
                  height: 18,
                  excludeFromSemantics: true,
                ),
                label: Text(
                  _googleWorking ? 'Opening Google…' : 'Continue with Google',
                ),
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Expanded(child: Divider(color: _border)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'or use email',
                      style: TextStyle(color: _paleBlue, fontSize: 10),
                    ),
                  ),
                  Expanded(child: Divider(color: _border)),
                ],
              ),
              const SizedBox(height: 14),
            ],
          )
        : const SizedBox.shrink(),
  );

  Widget _button(String label, VoidCallback? action, {IconData? icon}) =>
      FilledButton.icon(
        onPressed: action,
        style:
            FilledButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF204C7D),
              disabledForegroundColor: _paleBlue,
              minimumSize: const Size(0, 51),
              shape: const StadiumBorder(),
              side: const BorderSide(color: Color(0x94A5D1FF)),
            ).copyWith(
              animationDuration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return const Color(0xFF204C7D);
                }
                if (states.contains(WidgetState.pressed)) {
                  return const Color(0xFF023E7D);
                }
                if (states.contains(WidgetState.hovered)) {
                  return const Color(0xFF0353A4);
                }
                return _primary;
              }),
            ),
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 18),
        label: Text(label, textAlign: TextAlign.center),
        iconAlignment: IconAlignment.end,
      );

  Widget _stepContent() {
    final advancing = _register && _step != _SignUpStep.confirmation;
    final label = _working
        ? (_register ? 'Creating account…' : 'Logging in…')
        : advancing
        ? 'Continue'
        : _register
        ? 'Create account'
        : 'Log in';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_checkEmail)
          const Center(
            child: CircleAvatar(
              radius: 25,
              backgroundColor: Color(0x504384CE),
              child: Icon(Icons.mark_email_read_outlined, color: _bright),
            ),
          )
        else if (_register)
          _SignUpProgress(step: _step),
        if (_register) const SizedBox(height: 15),
        Semantics(
          header: true,
          child: Text(
            _title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontVariations: [FontVariation('wght', 800)],
              fontSize: 32,
              color: _bright,
              height: 1.12,
              letterSpacing: -1.45,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          liveRegion: _checkEmail,
          child: Text(
            _description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _paleBlue, fontSize: 12, height: 1.5),
          ),
        ),
        const SizedBox(height: 25),
        if (_checkEmail)
          _button(
            'Back to log in',
            _switchMode,
            icon: Icons.arrow_forward_rounded,
          )
        else ...[
          if (_details) ...[
            _google(),
            if (_register) ...[_nameField(), const SizedBox(height: 12)],
            _emailField(),
            if (!_register) ...[const SizedBox(height: 12), _passwordField()],
          ] else
            _passwordField(confirmation: _step == _SignUpStep.confirmation),
          if (_error case final message?) ...[
            const SizedBox(height: 13),
            AppNotice(message, tone: NoticeTone.error),
          ],
          const SizedBox(height: 19),
          _button(
            label,
            _busy ? null : _continue,
            icon: _working ? null : Icons.arrow_forward_rounded,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy
                ? null
                : _details
                ? _switchMode
                : () => _changeStep(_SignUpStep.values[_step.index - 1]),
            style: TextButton.styleFrom(foregroundColor: _paleBlue),
            child: Text(
              !_details
                  ? 'Back'
                  : _register
                  ? 'Already have an account? Log in'
                  : 'No account? Sign up',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: const BorderSide(color: _border),
    );
    final authTheme = theme.copyWith(
      textTheme: theme.textTheme.apply(
        fontFamily: 'Manrope',
        bodyColor: _bright,
        displayColor: _bright,
      ),
      colorScheme: theme.colorScheme.copyWith(
        primary: _paleBlue,
        error: _warning,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: _paleBlue,
        selectionColor: Color(0x7775AFFF),
        selectionHandleColor: _paleBlue,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: highContrast ? _night : const Color(0x5E001233),
        hoverColor: highContrast
            ? const Color(0xFF002855)
            : const Color(0x303B77BF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 15,
        ),
        prefixIconColor: _paleBlue,
        suffixIconColor: _paleBlue,
        labelStyle: const TextStyle(color: _paleBlue),
        floatingLabelStyle: const TextStyle(color: _bright),
        errorStyle: const TextStyle(color: _warning),
        border: border,
        enabledBorder: border,
        disabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: _paleBlue, width: 1.7),
        ),
        errorBorder: border.copyWith(
          borderSide: const BorderSide(color: _warning),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: const BorderSide(color: _warning, width: 1.7),
        ),
      ),
    );
    return Theme(
      data: authTheme,
      child: Scaffold(
        backgroundColor: _night,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (!highContrast) const _AuthBackdrop(),
            SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: TextButton.icon(
                        onPressed: _busy ? null : _home,
                        style: TextButton.styleFrom(foregroundColor: _paleBlue),
                        icon: const Icon(Icons.arrow_back_rounded, size: 17),
                        label: const Text('Back to home'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 34),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 458),
                          child: Column(
                            children: [
                              const CantiereWordmark(),
                              const SizedBox(height: 22),
                              GlassSurface(
                                radius: 29,
                                blur: 15,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    23,
                                    25,
                                    23,
                                    19,
                                  ),
                                  child: Form(
                                    key: _form,
                                    child: AutofillGroup(
                                      onDisposeAction:
                                          AutofillContextAction.cancel,
                                      child: AnimatedSwitcher(
                                        duration:
                                            MediaQuery.disableAnimationsOf(
                                              context,
                                            )
                                            ? Duration.zero
                                            : const Duration(milliseconds: 280),
                                        switchInCurve: Curves.easeOutCubic,
                                        layoutBuilder: (current, _) =>
                                            current ?? const SizedBox.shrink(),
                                        transitionBuilder: (child, animation) =>
                                            FadeTransition(
                                              opacity: animation,
                                              child: SlideTransition(
                                                position: animation.drive(
                                                  Tween(
                                                    begin: const Offset(
                                                      0,
                                                      .025,
                                                    ),
                                                    end: Offset.zero,
                                                  ),
                                                ),
                                                child: child,
                                              ),
                                            ),
                                        child: KeyedSubtree(
                                          key: ValueKey((
                                            _register,
                                            _step,
                                            _checkEmail,
                                          )),
                                          child: _stepContent(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignUpProgress extends StatelessWidget {
  const _SignUpProgress({required this.step});

  final _SignUpStep step;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        'Step ${step.index + 1} of ${_SignUpStep.values.length}',
        style: const TextStyle(
          color: _paleBlue,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      ExcludeSemantics(
        child: Row(
          children: [
            for (final item in _SignUpStep.values)
              Expanded(
                child: AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: item.index <= step.index ? _paleBlue : _border,
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _AuthBackdrop extends StatelessWidget {
  const _AuthBackdrop();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/landing/waterline.webp',
        fit: BoxFit.cover,
        alignment: const Alignment(.4, .1),
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xF0001233), Color(0xBF002855), Color(0xEB001233)],
          ),
        ),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(.33, -.26),
            radius: .8,
            colors: [Color(0x5B0466C8), Colors.transparent],
          ),
        ),
      ),
    ],
  );
}
