import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/error_log_service.dart';
import '../../ui/brand.dart';
import '../../ui/dialogs.dart';
import '../../ui/widgets.dart';
import 'forgot_password_screen.dart';
import 'otp_verification_view.dart';
import 'register_screen.dart';

enum _Step { credentials, loginCode, confirmEmail }

/// Sign in. The website's login card (email + password, "Forgot password?",
/// "Create an account", resend-confirmation when the email isn't confirmed),
/// plus passwordless sign-in with an emailed code. Signing in changes the
/// Supabase session, and MyApp's auth-state listener swaps to the app — no
/// navigation happens here.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  _Step _step = _Step.credentials;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.signInWithPassword(_email.text, _password.text);
    } on AuthProblem catch (e) {
      if (e.failure == AuthFailure.emailNotConfirmed) {
        if (mounted) setState(() => _error = e.message);
      } else {
        ErrorLogService.instance.log(LogCategory.auth, LogCode.passwordSignInFailed);
        if (mounted) setState(() => _error = e.message);
      }
      _needsConfirm = e.failure == AuthFailure.emailNotConfirmed;
    } catch (_) {
      ErrorLogService.instance.log(LogCategory.auth, LogCode.passwordSignInFailed);
      if (mounted) setState(() => _error = 'An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _needsConfirm = false;

  Future<void> _resendConfirmation() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.resendSignupCode(_email.text);
    } catch (_) {
      // The website shows the code screen regardless; a failed resend can be
      // retried from there.
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _step = _Step.confirmEmail;
      });
    }
  }

  Future<void> _sendLoginCode() async {
    final emailError = AuthService.validateEmail(_email.text);
    if (emailError != null) {
      setState(() => _error = emailError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.sendLoginCode(_email.text);
      if (mounted) setState(() => _step = _Step.loginCode);
    } on AuthProblem catch (e) {
      ErrorLogService.instance.log(LogCategory.auth, LogCode.otpSendFailed);
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      ErrorLogService.instance.log(LogCategory.auth, LogCode.otpSendFailed);
      if (mounted) setState(() => _error = 'Failed to send code. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _backToCredentials() => setState(() {
        _step = _Step.credentials;
        _error = null;
        _needsConfirm = false;
      });

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      child: AuthCard(
        child: switch (_step) {
          _Step.credentials => _credentials(context),
          _Step.loginCode => Column(
              children: [
                const AuthHeader(title: 'Enter your code', subtitle: 'Sign in with the code we emailed you'),
                OtpVerificationView(
                  email: _email.text.trim(),
                  instruction: 'Enter the 6-digit code from the email.',
                  onVerify: (code) async {
                    try {
                      await _auth.verifyLoginCode(_email.text, code);
                    } on AuthProblem {
                      ErrorLogService.instance.log(LogCategory.auth, LogCode.otpVerifyFailed);
                      rethrow;
                    }
                  },
                  onResend: () => _auth.sendLoginCode(_email.text),
                  onUseAnotherEmail: _backToCredentials,
                ),
              ],
            ),
          _Step.confirmEmail => Column(
              children: [
                const AuthHeader(title: 'Confirm your email', subtitle: 'One last step before you can sign in'),
                OtpVerificationView(
                  email: _email.text.trim(),
                  onVerify: (code) => _auth.verifySignupCode(_email.text, code),
                  onResend: () => _auth.resendSignupCode(_email.text),
                  onUseAnotherEmail: _backToCredentials,
                ),
              ],
            ),
        },
      ),
    );
  }

  Widget _credentials(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthHeader(
            title: 'Welcome Back',
            subtitle: 'Sign in to continue your learning journey',
          ),
          if (_error != null) ...[NoticeBanner(_error!), const SizedBox(height: 16)],
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            validator: AuthService.validateEmail,
            decoration: const InputDecoration(labelText: 'Email', hintText: 'you@example.com'),
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _password,
            validator: (v) => (v == null || v.isEmpty) ? 'Password is required' : null,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _signIn(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ForgotPasswordScreen(initialEmail: _email.text.trim()),
                ),
              ),
              child: const Text('Forgot password?'),
            ),
          ),
          const SizedBox(height: 4),
          GradientButton(
            label: _busy ? 'Signing in...' : 'Sign In',
            loading: _busy,
            onPressed: _busy ? null : _signIn,
          ),
          if (_needsConfirm) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : _resendConfirmation,
              child: const Text('Resend Email Confirmation'),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Divider(color: Brand.purple300)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or', style: nunito(13, 500, color: Brand.gray600)),
              ),
              const Expanded(child: Divider(color: Brand.purple300)),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _sendLoginCode,
            icon: const Icon(Icons.mark_email_read_outlined),
            label: const Text('Email me a sign-in code'),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text("Don't have an account? ", style: nunito(14, 400, color: Brand.gray600)),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RegisterScreen()),
                ),
                child: Text('Create an account',
                    style: nunito(14, 700, color: Brand.purpleLight)),
              ),
            ],
          ),
          TextButton(
            onPressed: () => launchSupportEmail(context, subject: 'Vasis Beats sign-in help'),
            child: Text('Contact support', style: nunito(14, 600, color: Brand.gray600)),
          ),
        ],
      ),
    );
  }
}
