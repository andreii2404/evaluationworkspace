import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../services/cloud_repository.dart';
import '../widgets/app_notice.dart';
import '../widgets/cantiere_wordmark.dart';
import '../widgets/workspace_select.dart';
import 'account_setup_screen.dart';
import 'workspace_forms.dart';

class AccountSecurityGate extends StatelessWidget {
  const AccountSecurityGate({
    super.key,
    required this.client,
    required this.recovery,
    required this.finishRecovery,
    required this.child,
  });
  final SupabaseClient client;
  final bool recovery;
  final VoidCallback finishRecovery;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = client.auth;
    final user = auth.currentUser!;
    final assurance = auth.mfa.getAuthenticatorAssuranceLevel();
    final needsMfa =
        assurance.currentLevel != AuthenticatorAssuranceLevels.aal2 &&
        (assurance.nextLevel == AuthenticatorAssuranceLevels.aal2 ||
            user.appMetadata['evalink_moderator'] == true);
    if (!needsMfa && !recovery) return child;
    return Theme(
      data: workshopTheme(Theme.of(context)),
      child: needsMfa
          ? _SecurityChallenge(client: client, key: ValueKey(user.id))
          : _ResetPassword(
              client: client,
              onDone: finishRecovery,
              key: ValueKey(user.id),
            ),
    );
  }
}

Widget _codeField(
  TextEditingController controller, {
  bool enabled = true,
  VoidCallback? submit,
}) => TextFormField(
  controller: controller,
  enabled: enabled,
  keyboardType: TextInputType.number,
  autofillHints: const [AutofillHints.oneTimeCode],
  decoration: const InputDecoration(labelText: 'Authenticator code'),
  inputFormatters: [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(6),
  ],
  validator: (value) => value?.length == 6 ? null : 'Enter the six-digit code.',
  onFieldSubmitted: (_) => submit?.call(),
);

List<Factor> _totpFactors(GoTrueClient auth) =>
    (auth.currentUser?.factors ?? [])
        .where(
          (factor) =>
              factor.factorType == FactorType.totp &&
              factor.status == FactorStatus.verified,
        )
        .toList();

Future<void> _verifyAuthenticator(
  GoTrueClient auth,
  String factorId,
  String code,
) async {
  try {
    await auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  } on AuthException catch (error) {
    if (error.statusCode == '429') rethrow;
    if (const {
      'mfa_verification_failed',
      'mfa_challenge_expired',
      'validation_failed',
    }.contains(error.code)) {
      throw const FormatException(
        'That code didn’t match. Use the current In Cantiere code from your authenticator app. If it still fails, check that your phone’s time is set automatically.',
      );
    }
    rethrow;
  }
}

class _SecurityChallenge extends StatefulWidget {
  const _SecurityChallenge({super.key, required this.client});
  final SupabaseClient client;

  @override
  State<_SecurityChallenge> createState() => _SecurityChallengeState();
}

class _SecurityChallengeState extends State<_SecurityChallenge> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  String? _selected;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = workspaceError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _verify(String factorId) async {
    if (!validateAndReveal(_form)) return;
    await _run(
      () => _verifyAuthenticator(widget.client.auth, factorId, _code.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.client.auth;
    final factors = _totpFactors(auth);
    final id = _selected ?? factors.firstOrNull?.id;
    final needsEnrollment =
        id == null &&
        auth.mfa.getAuthenticatorAssuranceLevel().nextLevel !=
            AuthenticatorAssuranceLevels.aal2;
    return AccountSetupFrame(
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            const CantiereWordmark(fontSize: 24),
            Text(
              needsEnrollment
                  ? 'Set up two-step verification'
                  : 'Verify your sign-in',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (needsEnrollment)
              const Text(
                'Moderator accounts use an authenticator app to protect access to the workspace.',
              )
            else if (id != null)
              const Text(
                'Open your authenticator app and enter the current six-digit In Cantiere code. You can use an enrolled backup device.',
              )
            else
              const Text(
                'No supported authenticator is available for this session. Sign out and contact your workspace administrator.',
              ),
            if (factors.length > 1)
              WorkspaceSelect<String>(
                label: 'Authenticator',
                initial: id,
                choices: {
                  for (final (index, factor) in factors.indexed)
                    factor.id:
                        factor.friendlyName ?? 'Authenticator ${index + 1}',
                },
                onChanged: (value) => setState(() => _selected = value),
              ),
            if (id != null)
              _codeField(_code, enabled: !_working, submit: () => _verify(id)),
            if (_error case final message?)
              AppNotice(message, tone: NoticeTone.error),
            if (needsEnrollment)
              FilledButton(
                onPressed: _working
                    ? null
                    : () => enrollAuthenticator(context, auth),
                child: const Text('Set up authenticator'),
              )
            else if (id != null)
              FilledButton(
                onPressed: _working ? null : () => _verify(id),
                child: Text(_working ? 'Verifying…' : 'Verify'),
              ),
            TextButton(
              onPressed: _working
                  ? null
                  : () => _run(() => auth.signOut(scope: SignOutScope.local)),
              child: const Text('Back to log in'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResetPassword extends StatefulWidget {
  const _ResetPassword({super.key, required this.client, required this.onDone});
  final SupabaseClient client;
  final VoidCallback onDone;

  @override
  State<_ResetPassword> createState() => _ResetPasswordState();
}

class _ResetPasswordState extends State<_ResetPassword> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_working || !validateAndReveal(_form)) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.client.auth.updateUser(
        UserAttributes(password: _password.text),
      );
      if (mounted) {
        TextInput.finishAutofillContext(shouldSave: true);
        widget.onDone();
      }
    } catch (error) {
      if (mounted) setState(() => _error = workspaceError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => AccountSetupFrame(
    child: AutofillGroup(
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            const CantiereWordmark(fontSize: 24),
            Text(
              'Choose a new password',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            TextFormField(
              controller: _password,
              enabled: !_working,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'New password'),
              validator: (value) => (value?.length ?? 0) < 8
                  ? 'Use at least 8 characters.'
                  : null,
            ),
            TextFormField(
              enabled: !_working,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm password'),
              validator: (value) => value == _password.text && value!.isNotEmpty
                  ? null
                  : 'Passwords don’t match.',
              onFieldSubmitted: (_) => _save(),
            ),
            if (_error case final message?)
              AppNotice(message, tone: NoticeTone.error),
            FilledButton(
              onPressed: _working ? null : _save,
              child: Text(_working ? 'Saving…' : 'Save password'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> enrollAuthenticator(
  BuildContext context,
  GoTrueClient auth,
) async {
  final added = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AuthenticatorEnrollment(auth: auth),
  );
  return added == true;
}

class _AuthenticatorEnrollment extends StatefulWidget {
  const _AuthenticatorEnrollment({required this.auth});
  final GoTrueClient auth;

  @override
  State<_AuthenticatorEnrollment> createState() =>
      _AuthenticatorEnrollmentState();
}

class _AuthenticatorEnrollmentState extends State<_AuthenticatorEnrollment> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  late Future<AuthMFAEnrollResponse> _enrollment = _start();
  bool _confirmed = false;

  Future<AuthMFAEnrollResponse> _start() async {
    final auth = widget.auth;
    final user = (await auth.getUser()).user;
    // Abandoned enrollments are unverified and cannot protect an account.
    for (final factor in user?.factors ?? <Factor>[]) {
      if (factor.factorType == FactorType.totp &&
          factor.status == FactorStatus.unverified) {
        await auth.mfa.unenroll(factor.id);
      }
    }
    return auth.mfa.enroll(issuer: cantiereName);
  }

  @override
  void dispose() {
    _code.dispose();
    if (!_confirmed) {
      final auth = widget.auth;
      final userId = auth.currentUser?.id;
      _enrollment
          .then<void>((factor) async {
            if (userId != null && auth.currentUser?.id == userId) {
              await auth.mfa.unenroll(factor.id);
            }
          })
          .catchError((Object _) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _enrollment,
    builder: (_, snapshot) {
      final enrollment = snapshot.data;
      final secret = enrollment?.totp?.secret;
      return WorkspaceDialogForm(
        title: 'Add an authenticator',
        action: 'Verify and enable',
        onSave: enrollment == null
            ? null
            : () async {
                if (!validateAndReveal(_form)) return false;
                await _verifyAuthenticator(
                  widget.auth,
                  enrollment.id,
                  _code.text,
                );
                _confirmed = true;
                return true;
              },
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              if (snapshot.hasError) ...[
                AppNotice(
                  workspaceError(snapshot.error!),
                  tone: NoticeTone.error,
                ),
                TextButton(
                  onPressed: () => setState(() => _enrollment = _start()),
                  child: const Text('Try again'),
                ),
              ] else if (secret == null)
                const Text('Preparing your authenticator…')
              else ...[
                const Text(
                  'Scan this QR code with your authenticator app or enter the setup key. If you set this up before, use the new entry you add here.',
                ),
                Center(
                  child: QrImageView(
                    data: enrollment?.totp?.uri ?? '',
                    size: 152,
                    backgroundColor: Colors.white,
                    semanticsLabel: 'QR code for authenticator setup',
                  ),
                ),
                SelectableText(secret, textAlign: TextAlign.center),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: secret));
                    if (context.mounted) {
                      AppNotice.show(context, 'Setup key copied.');
                    }
                  },
                  icon: const Icon(Icons.copy_outlined, size: 17),
                  label: const Text('Copy setup key'),
                ),
                _codeField(_code),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class AccountSecuritySettings extends StatefulWidget {
  const AccountSecuritySettings({super.key, required this.client});
  final SupabaseClient client;

  @override
  State<AccountSecuritySettings> createState() =>
      _AccountSecuritySettingsState();
}

class _AccountSecuritySettingsState extends State<AccountSecuritySettings> {
  @override
  Widget build(BuildContext context) {
    final auth = widget.client.auth;
    final factors = _totpFactors(auth);
    final required = auth.currentUser?.appMetadata['evalink_moderator'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(
          'Two-step verification',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          factors.isEmpty
              ? 'Protect your sign-ins with a code from an authenticator app.'
              : 'Two-step verification is enabled. Add a backup authenticator on another device in case you lose access.',
        ),
        for (final (index, factor) in factors.indexed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(factor.friendlyName ?? 'Authenticator ${index + 1}'),
            trailing: required && factors.length == 1
                ? null
                : TextButton(
                    onPressed: () async {
                      final removed = await confirmWorkspaceAction(
                        context,
                        title: 'Remove authenticator?',
                        action: 'Remove authenticator',
                        message: factors.length == 1
                            ? 'Future sign-ins will no longer ask for an authenticator code.'
                            : 'You will need to use another enrolled authenticator at your next sign-in.',
                        destructive: true,
                        perform: () async {
                          await auth.mfa.unenroll(factor.id);
                          await auth.refreshSession();
                        },
                      );
                      if (mounted && removed) setState(() {});
                    },
                    child: const Text('Remove'),
                  ),
          ),
        OutlinedButton(
          onPressed: () async {
            final added = await enrollAuthenticator(context, auth);
            if (mounted && added) setState(() {});
          },
          child: Text(
            factors.isEmpty
                ? 'Set up authenticator'
                : 'Add backup authenticator',
          ),
        ),
      ],
    );
  }
}
