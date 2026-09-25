import 'package:flutter/material.dart';
import 'package:phone_form_field/phone_form_field.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';
import '../../ui/brand.dart';
import '../../ui/widgets.dart';
import 'otp_verification_view.dart';

/// Currency by country, exactly as the website derives it from the phone
/// number's country (anything else is USD).
const Map<String, String> _currencyByCountry = {
  'US': 'USD', 'GB': 'GBP', 'BR': 'BRL', 'IN': 'INR', 'CA': 'CAD',
  'AU': 'AUD', 'JP': 'JPY', 'ES': 'EUR', 'PT': 'EUR',
};

/// Create an account — same form, rules and metadata as the website's
/// registration, so the account works there immediately (and the person
/// finishes their profile there, on first visit, if they want to).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _legalName = TextEditingController();
  final _spiritualName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _phone = PhoneController();

  String _language = 'en';
  bool _agree = false;
  bool _showAgreeError = false;
  bool _busy = false;
  bool _registered = false;
  String? _error;

  @override
  void dispose() {
    _legalName.dispose();
    _spiritualName.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState?.validate() ?? false;
    setState(() => _showAgreeError = !_agree);
    if (!valid || !_agree) return;

    final phone = _phone.value;
    final country = phone.isoCode.name.toUpperCase();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.signUp(SignUpData(
        email: _email.text,
        password: _password.text,
        legalName: _legalName.text,
        spiritualName: _spiritualName.text.trim().isEmpty ? null : _spiritualName.text,
        phoneE164: phone.international,
        countryIso: country,
        currency: _currencyByCountry[country] ?? 'USD',
        preferredLanguage: _language,
      ));
      if (mounted) setState(() => _registered = true);
    } on AuthProblem catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      child: AuthCard(
        child: _registered ? _confirmStep() : _form(context),
      ),
    );
  }

  Widget _confirmStep() {
    return Column(
      children: [
        const AuthHeader(title: 'Registration successful!'),
        const NoticeBanner('Please check your email to confirm your account.',
            kind: NoticeKind.success),
        const SizedBox(height: 20),
        OtpVerificationView(
          email: _email.text.trim(),
          onVerify: (code) async {
            await _auth.verifySignupCode(_email.text, code);
            // Confirmed and signed in: the app swaps in automatically; close
            // this screen (and login beneath it) so nothing lingers.
            if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
          },
          onResend: () => _auth.resendSignupCode(_email.text),
          onUseAnotherEmail: () => setState(() => _registered = false),
        ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthHeader(
            title: 'Create Your Account',
            subtitle: 'Join thousands of learners on their musical journey',
          ),
          if (_error != null) ...[NoticeBanner(_error!), const SizedBox(height: 16)],
          Text('Preferred language', style: nunito(14, 600, color: Brand.gray700)),
          RadioGroup<String>(
            groupValue: _language,
            onChanged: (v) => setState(() => _language = v ?? 'en'),
            child: Wrap(
              spacing: 8,
              children: const [
                _LangRadio('en', 'English'),
                _LangRadio('es', 'Español'),
                _LangRadio('pt', 'Português'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _legalName,
            textInputAction: TextInputAction.next,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Legal name is required' : null,
            decoration: const InputDecoration(labelText: 'Legal name'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _spiritualName,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Spiritual name (optional)'),
          ),
          const SizedBox(height: 16),
          PhoneFormField(
            controller: _phone,
            validator: PhoneValidator.compose([
              PhoneValidator.required(context, errorText: 'Whatsapp number is required'),
              PhoneValidator.valid(context, errorText: 'Whatsapp number is invalid'),
            ]),
            countrySelectorNavigator: const CountrySelectorNavigator.dialog(),
            decoration: const InputDecoration(labelText: 'Whatsapp number'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            validator: AuthService.validateEmail,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _password,
            hint: 'Must be at least 8 characters with uppercase, lowercase, and number',
            validator: AuthService.validateRegisterPassword,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _confirm,
            label: 'Confirm password',
            validator: (v) {
              if (v == null || v.isEmpty) return 'Please confirm your password';
              if (v != _password.text) return 'Passwords do not match';
              return null;
            },
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: _agree, onChanged: (v) => setState(() => _agree = v ?? false)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('I agree to the ', style: nunito(13, 400, color: Brand.gray700)),
                      _Link('Terms & Conditions', 'https://www.vasisstudio.com/terms'),
                      Text(' and ', style: nunito(13, 400, color: Brand.gray700)),
                      _Link('Privacy Policy', 'https://www.vasisstudio.com/privacy'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_showAgreeError && !_agree)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text('You must agree to the terms and conditions',
                  style: nunito(13, 400, color: Brand.error)),
            ),
          const SizedBox(height: 8),
          GradientButton(
            label: _busy ? 'Creating account...' : 'Create Account',
            loading: _busy,
            onPressed: _busy ? null : _submit,
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Already have an account? ', style: nunito(14, 400, color: Brand.gray600)),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Text('Sign in', style: nunito(14, 700, color: Brand.purpleLight)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LangRadio extends StatelessWidget {
  final String value;
  final String label;
  const _LangRadio(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<String>(value: value),
        Text(label, style: nunito(14, 500, color: Brand.gray700)),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  final String text;
  final String url;
  const _Link(this.text, this.url);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Text(text, style: nunito(13, 700, color: Brand.purpleLight)),
    );
  }
}
