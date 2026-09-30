import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'welcome_email.dart';

const String _websiteOrigin = 'https://www.vasisstudio.com';

/// What the registration form collects. Narrower than the website's form:
/// first and last name only (saved together as the legal name, no spiritual
/// name), no phone number, and English as the language.
class SignUpData {
  final String email;
  final String password;
  final String firstName;
  final String lastName;

  const SignUpData({
    required this.email,
    required this.password,
    required this.firstName,
    required this.lastName,
  });

  String get legalName => '${firstName.trim()} ${lastName.trim()}'.trim();
}

/// Why a login/registration step failed, in terms the UI can act on.
enum AuthFailure {
  emailNotConfirmed,
  invalidCredentials,
  emailAlreadyRegistered,
  noAccount,
  other,
}

class AuthProblem implements Exception {
  final AuthFailure failure;
  final String message;
  AuthProblem(this.failure, this.message);
  @override
  String toString() => message;
}

/// The single place the app talks to Supabase Auth, mirroring the website's
/// `src/lib/supabase/auth.ts` so an account made on either works on both:
/// same email normalisation, same `verifyOtp` type for signup confirmation,
/// same signup metadata keys, same welcome email and contact-list sync.
///
/// Two deliberate differences from the website, both for safety:
///  * `role` is never sent. The database trigger trusts client-supplied
///    metadata for it and defaults to 'student' when absent.
///  * `password_hash` is sent as the placeholder 'app', not the plaintext
///    password (nothing reads that column; the website stores the real
///    password there, which it shouldn't).
class AuthService {
  SupabaseClient get _client => Supabase.instance.client;

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  // -- validation (same rules and wording as the website) ---------------

  static String? validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required';
    if (!RegExp(r'\S+@\S+\.\S+').hasMatch(v)) return 'Email is invalid';
    return null;
  }

  static String? validateRegisterPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Password must be at least 8 characters';
    if (!RegExp(r'(?=.*[a-z])(?=.*[A-Z])(?=.*\d)').hasMatch(v)) {
      return 'Password must contain at least one uppercase letter, one lowercase letter, and one number';
    }
    return null;
  }

  static String? validateNewPassword(String? value) {
    if ((value ?? '').length < 8) return 'Password must be at least 8 characters long.';
    return null;
  }

  // -- sign in -----------------------------------------------------------

  Future<void> signInWithPassword(String email, String password) async {
    try {
      await _client.auth.signInWithPassword(email: normalizeEmail(email), password: password);
    } on AuthException catch (e) {
      throw _map(e);
    }
  }

  /// Passwordless login code for an existing account. Never creates one —
  /// accounts are made through [signUp], exactly like the website.
  Future<void> sendLoginCode(String email) async {
    try {
      await _client.auth.signInWithOtp(email: normalizeEmail(email), shouldCreateUser: false);
    } on AuthException catch (e) {
      throw _map(e);
    }
  }

  Future<void> verifyLoginCode(String email, String code) => _verifyEmailCode(email, code);

  // -- sign up -----------------------------------------------------------

  /// Registers an account and leaves the person needing to confirm their
  /// email with the 6-digit code (see [verifySignupCode]). Order matches the
  /// website: contact-list sync, then signUp, then the welcome email (best
  /// effort).
  Future<void> signUp(SignUpData data) async {
    final email = normalizeEmail(data.email);
    final displayName = data.legalName;

    await _syncContact(email, displayName);

    try {
      final response = await _client.auth.signUp(
        email: email,
        password: data.password,
        emailRedirectTo: '$_websiteOrigin/register/complete-profile?source=app',
        data: {
          'password_hash': 'app',
          'initiated_name': '',
          'legal_name': data.legalName,
          // No phone, so no country to derive a currency from: USD is the
          // website's fallback for any country it doesn't price locally.
          'currency': 'USD',
          'is_active': true,
          'email_verified': false,
          'preferred_language': 'en',
        },
      );
      if (response.user?.id != null) {
        _sendWelcomeEmail(email, displayName);
      }
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('duplicate key value violates unique constraint')) {
        throw AuthProblem(AuthFailure.emailAlreadyRegistered,
            'Email already registered. Please sign in.');
      }
      throw _map(e);
    }
  }

  /// Confirms a new account. `type: email`, as on the website's OTP screen.
  Future<void> verifySignupCode(String email, String code) => _verifyEmailCode(email, code);

  Future<void> resendSignupCode(String email) async {
    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: normalizeEmail(email),
        emailRedirectTo: '$_websiteOrigin/register/complete-profile?source=app',
      );
    } on AuthException catch (e) {
      throw _map(e);
    }
  }

  Future<void> _verifyEmailCode(String email, String code) async {
    try {
      await _client.auth
          .verifyOTP(email: normalizeEmail(email), token: code.trim(), type: OtpType.email);
    } on AuthException {
      throw AuthProblem(AuthFailure.other, 'Invalid or expired code. Please try again.');
    }
  }

  // -- password recovery -------------------------------------------------

  /// Sends the reset email. The recovery email must include the 6-digit
  /// `{{ .Token }}` for the in-app code flow ([verifyRecoveryCode]); its
  /// link alone can't be completed from the app, because the PKCE
  /// verifier for it lives in the app, not the browser.
  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        normalizeEmail(email),
        redirectTo: '$_websiteOrigin/reset-password',
      );
    } on AuthException catch (e) {
      throw _map(e);
    }
  }

  Future<void> verifyRecoveryCode(String email, String code) async {
    try {
      await _client.auth
          .verifyOTP(email: normalizeEmail(email), token: code.trim(), type: OtpType.recovery);
    } on AuthException {
      throw AuthProblem(AuthFailure.other, 'Invalid or expired code. Please try again.');
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw _map(e);
    }
  }

  /// Change password while signed in: re-verifies the current password
  /// first, exactly as the website's change-password page does.
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final email = _client.auth.currentUser?.email;
    if (email == null) throw AuthProblem(AuthFailure.other, 'You are not signed in.');
    try {
      await _client.auth.signInWithPassword(email: email, password: currentPassword);
    } on AuthException {
      throw AuthProblem(AuthFailure.invalidCredentials, 'Current password is incorrect.');
    }
    await updatePassword(newPassword);
  }

  Future<void> signOut() => _client.auth.signOut();

  // -- website integrations (best effort) ---------------------------------

  /// Adds the person to the marketing contact list the website uses
  /// (`/api/brevo`, list 19). Best effort — no phone number is collected,
  /// so the website's duplicate-number conflict can't happen here, and a
  /// failure (offline, outage) never blocks registration.
  Future<void> _syncContact(String email, String displayName) async {
    try {
      await Dio().post(
        '$_websiteOrigin/api/brevo',
        data: {
          'email': email,
          'name': displayName,
          'listId': 19,
          'source': 'app',
          'language': 'en',
        },
      );
    } catch (_) {}
  }

  void _sendWelcomeEmail(String email, String name) {
    Dio()
        .post(
          '$_websiteOrigin/api/brevo/send-email',
          data: {
            'to': [
              {'email': email, 'name': name}
            ],
            'subject': welcomeEmailSubject,
            'htmlContent': welcomeEmailHtml,
          },
        )
        .catchError((_) => Response(requestOptions: RequestOptions()));
  }

  // -- error mapping -------------------------------------------------------

  AuthProblem _map(AuthException e) {
    final msg = e.message;
    if (msg == 'Email not confirmed') {
      return AuthProblem(AuthFailure.emailNotConfirmed,
          'Please check your inbox and confirm your email.');
    }
    if (msg == 'Invalid login credentials') {
      return AuthProblem(AuthFailure.invalidCredentials,
          'The email or password you entered is incorrect. Please try again.');
    }
    if (e.code == 'otp_disabled' || msg.contains('Signups not allowed for otp')) {
      return AuthProblem(AuthFailure.noAccount,
          'No account found for that email. Please create an account first.');
    }
    return AuthProblem(AuthFailure.other, msg);
  }
}
