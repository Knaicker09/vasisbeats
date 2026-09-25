import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/error_log_service.dart';
import '../../ui/brand.dart';
import '../../ui/widgets.dart';

/// Forgot password, in two steps: request the email, then enter the 6-digit
/// code from it with a new password. (The link in that email can't be
/// completed from the app — see AuthService.sendPasswordReset — so the code
/// is what works, and it needs `{{ .Token }}` in the Recovery email
/// template.)
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _auth = AuthService();
  final _emailKey = GlobalKey<FormState>();
  final _passwordKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();

  bool _codeSent = false;
  bool _verified = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendEmail() async {
    if (!(_emailKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.sendPasswordReset(_email.text);
      if (mounted) {
        setState(() {
          _codeSent = true;
          _info = 'Password reset email sent. Please check your inbox.';
        });
      }
    } on AuthProblem catch (e) {
      ErrorLogService.instance.log(LogCategory.auth, LogCode.passwordResetFailed);
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      ErrorLogService.instance.log(LogCategory.auth, LogCode.passwordResetFailed);
      if (mounted) setState(() => _error = 'Unexpected error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updatePassword() async {
    if (!(_passwordKey.currentState?.validate() ?? false)) return;
    if (_code.text.length != 6 && !_verified) {
      setState(() => _error = 'Please enter all 6 digits.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      // Verifying the code signs the person in; keep that separate so a
      // failed password update can be retried without re-verifying.
      if (!_verified) {
        await _auth.verifyRecoveryCode(_email.text, _code.text);
        _verified = true;
      }
      await _auth.updatePassword(_password.text);
      if (mounted) {
        setState(() => _info = 'Your password has been updated successfully.');
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } on AuthProblem catch (e) {
      ErrorLogService.instance.log(LogCategory.auth, LogCode.passwordResetFailed);
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unexpected error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      child: AuthCard(
        plain: true,
        child: _codeSent ? _resetStep() : _emailStep(),
      ),
    );
  }

  Widget _emailStep() {
    return Form(
      key: _emailKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthHeader(
            title: 'Forgot Password',
            subtitle: 'Enter your email to receive a reset link.',
            badgeIcon: Icons.lock_outline,
          ),
          if (_error != null) ...[NoticeBanner(_error!), const SizedBox(height: 16)],
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            validator: AuthService.validateEmail,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 20),
          GradientButton(
            label: _busy ? 'Sending...' : 'Send Reset Link',
            loading: _busy,
            onPressed: _busy ? null : _sendEmail,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to login'),
          ),
        ],
      ),
    );
  }

  Widget _resetStep() {
    return Form(
      key: _passwordKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthHeader(
            title: 'Reset Password',
            subtitle: 'Enter the 6-digit code from the email and choose a new password.',
            badgeIcon: Icons.lock_reset,
          ),
          if (_info != null) ...[
            NoticeBanner(_info!, kind: NoticeKind.success),
            const SizedBox(height: 16),
          ],
          if (_error != null) ...[NoticeBanner(_error!), const SizedBox(height: 16)],
          OtpCodeField(controller: _code),
          const SizedBox(height: 20),
          PasswordField(
            controller: _password,
            label: 'New password',
            validator: AuthService.validateNewPassword,
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _confirm,
            label: 'Confirm password',
            validator: (v) => v != _password.text ? 'Passwords do not match.' : null,
          ),
          const SizedBox(height: 20),
          GradientButton(
            label: _busy ? 'Updating...' : 'Update Password',
            loading: _busy,
            onPressed: _busy ? null : _updatePassword,
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        try {
                          await _auth.sendPasswordReset(_email.text);
                          if (mounted) {
                            setState(() => _info = 'A new code has been sent to your email.');
                          }
                        } catch (_) {
                          if (mounted) {
                            setState(() => _error = 'Failed to resend code. Please try again.');
                          }
                        }
                      },
                child: const Text('Resend code'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _codeSent = false;
                  _error = null;
                  _info = null;
                }),
                child: const Text('Use another email'),
              ),
            ],
          ),
          Text(
            'Tip: the code is valid for a short time. Nothing arrived? Check your spam folder.',
            textAlign: TextAlign.center,
            style: nunito(12, 400, color: Brand.gray500),
          ),
        ],
      ),
    );
  }
}
