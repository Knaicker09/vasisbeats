import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../ui/brand.dart';
import '../../ui/dialogs.dart';
import '../../ui/widgets.dart';

/// The 6-digit code step, wording and behaviour as on the website's OTP
/// screen: auto-submits on the sixth digit, resend with a 60-second
/// cooldown, plus the recovery controls — resend, use another email,
/// contact support.
class OtpVerificationView extends StatefulWidget {
  final String email;
  final String instruction;
  final Future<void> Function(String code) onVerify;
  final Future<void> Function() onResend;
  final VoidCallback onUseAnotherEmail;

  const OtpVerificationView({
    super.key,
    required this.email,
    required this.onVerify,
    required this.onResend,
    required this.onUseAnotherEmail,
    this.instruction = 'Click the link in the email, or enter the 6-digit code below.',
  });

  @override
  State<OtpVerificationView> createState() => _OtpVerificationViewState();
}

class _OtpVerificationViewState extends State<OtpVerificationView> {
  static const _cooldownSeconds = 60;

  final _code = TextEditingController();
  bool _verifying = false;
  bool _resending = false;
  String? _error;
  String? _info;
  int _cooldown = _cooldownSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {
        _cooldown--;
        if (_cooldown <= 0) t.cancel();
      });
    });
  }

  Future<void> _verify([String? typed]) async {
    final code = typed ?? _code.text;
    if (code.length != 6) {
      setState(() => _error = 'Please enter all 6 digits.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
      _info = null;
    });
    try {
      await widget.onVerify(code);
    } on AuthProblem catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Invalid or expired code. Please try again.');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
      _info = null;
    });
    try {
      await widget.onResend();
      if (mounted) {
        setState(() => _info = 'A new code has been sent to your email.');
        _startCooldown();
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to resend code. Please try again.');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'We sent a code to ${widget.email}.',
          textAlign: TextAlign.center,
          style: nunito(14, 600, color: Brand.gray700),
        ),
        const SizedBox(height: 4),
        Text(widget.instruction,
            textAlign: TextAlign.center, style: nunito(14, 400, color: Brand.gray600)),
        const SizedBox(height: 20),
        OtpCodeField(controller: _code, onCompleted: _verify),
        const SizedBox(height: 16),
        if (_error != null) ...[NoticeBanner(_error!), const SizedBox(height: 12)],
        if (_info != null) ...[
          NoticeBanner(_info!, kind: NoticeKind.success),
          const SizedBox(height: 12),
        ],
        GradientButton(
          label: _verifying ? 'Verifying...' : 'Verify Code',
          loading: _verifying,
          onPressed: _verifying ? null : _verify,
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text("Didn't get it? ", style: nunito(14, 400, color: Brand.gray600)),
            TextButton(
              onPressed: (_cooldown > 0 || _resending) ? null : _resend,
              child: Text(_resending
                  ? 'Resending...'
                  : _cooldown > 0
                      ? 'Resend code in ${_cooldown}s'
                      : 'Resend code'),
            ),
          ],
        ),
        TextButton(onPressed: widget.onUseAnotherEmail, child: const Text('Use another email')),
        TextButton(
          onPressed: () => launchSupportEmail(context, subject: 'Vasis Beats sign-in help'),
          child: Text('Contact support', style: nunito(14, 600, color: Brand.gray600)),
        ),
      ],
    );
  }
}
