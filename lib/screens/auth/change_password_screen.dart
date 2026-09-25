import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../ui/widgets.dart';

/// Change password while signed in (the website's /change-password): the
/// current password is verified first.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      await _auth.changePassword(_current.text, _new.text);
      if (mounted) {
        setState(() => _success = 'Your password has been changed successfully.');
        _current.clear();
        _new.clear();
        _confirm.clear();
      }
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
        plain: true,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthHeader(
                title: 'Change Password',
                subtitle: 'Enter your current password and choose a new one.',
                badgeIcon: Icons.lock_outline,
              ),
              if (_error != null) ...[NoticeBanner(_error!), const SizedBox(height: 16)],
              if (_success != null) ...[
                NoticeBanner(_success!, kind: NoticeKind.success),
                const SizedBox(height: 16),
              ],
              PasswordField(
                controller: _current,
                label: 'Current password',
                validator: (v) => (v == null || v.isEmpty) ? 'Current password is required.' : null,
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _new,
                label: 'New password',
                validator: (v) => (v ?? '').length < 8
                    ? 'New password must be at least 8 characters long.'
                    : null,
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _confirm,
                label: 'Confirm new password',
                validator: (v) =>
                    v != _new.text ? 'New password and confirm password do not match.' : null,
              ),
              const SizedBox(height: 20),
              GradientButton(
                label: _busy ? 'Changing...' : 'Change Password',
                loading: _busy,
                onPressed: _busy ? null : _submit,
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
            ],
          ),
        ),
      ),
    );
  }
}
