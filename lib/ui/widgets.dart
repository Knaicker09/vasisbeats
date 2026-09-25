import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';

/// The website's primary CTA: horizontal purple gradient, 8px radius,
/// hover → darker gradient + slight scale, spinner while working.
class GradientButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expanded;
  final bool pill;

  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expanded = true,
    this.pill = false,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final radius = BorderRadius.circular(widget.pill ? Brand.pill : Brand.radius);

    final content = Row(
      mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        else if (widget.icon != null)
          Icon(widget.icon, size: 20, color: Colors.white),
        if (widget.loading || widget.icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            widget.label,
            style: nunito(15, 600, color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover && enabled ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Opacity(
          opacity: widget.onPressed == null && !widget.loading ? 0.5 : 1,
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                gradient: _hover && enabled ? Brand.primaryGradientHover : Brand.primaryGradient,
                borderRadius: radius,
                boxShadow: Brand.cardShadow,
              ),
              child: InkWell(
                onTap: enabled ? widget.onPressed : null,
                borderRadius: radius,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Public-site style page for sign in / register / password screens: flat
/// #d0d0d0 backdrop, white nav bar with the logo mark, centred card.
class AuthShell extends StatelessWidget {
  final Widget child;
  const AuthShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.authBackdrop,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Image.asset('images/logo_without_text.png', height: 48),
                  const SizedBox(width: 8),
                  Text('Vasis Studio', style: nunito(24, 700, color: Brand.purple500)),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 448),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rounded auth card. Sign in / register use the purple-fading card;
/// password screens use a plain white one.
class AuthCard extends StatelessWidget {
  final Widget child;
  final bool plain;
  const AuthCard({super.key, required this.child, this.plain = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: plain ? Colors.white : null,
        gradient: plain
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Brand.purple300, Brand.purple300.withValues(alpha: 0)],
              ),
        borderRadius: BorderRadius.circular(Brand.authCardRadius),
        boxShadow: Brand.authShadow,
      ),
      child: child,
    );
  }
}

/// Title block used at the top of auth cards: logo (or icon badge),
/// heading, subtitle.
class AuthHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? badgeIcon;
  const AuthHeader({super.key, required this.title, this.subtitle, this.badgeIcon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (badgeIcon != null)
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Brand.primaryGradient),
            child: Icon(badgeIcon, color: Colors.white, size: 30),
          )
        else
          Image.asset('images/logo.png', height: 120, width: 120, fit: BoxFit.contain),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: nunito(30, 700, color: Brand.gray900)),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, textAlign: TextAlign.center, style: nunito(15, 400, color: Brand.gray600)),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

enum NoticeKind { error, success }

/// Error / success banner as on the website's forms.
class NoticeBanner extends StatelessWidget {
  final String message;
  final NoticeKind kind;
  const NoticeBanner(this.message, {super.key, this.kind = NoticeKind.error});

  @override
  Widget build(BuildContext context) {
    final isError = kind == NoticeKind.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isError ? Brand.errorBg : Brand.successBg,
        border: Border.all(color: isError ? Brand.errorBorder : Brand.successBorder),
        borderRadius: BorderRadius.circular(Brand.radius),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: nunito(14, 500, color: isError ? Brand.error : Brand.successText),
      ),
    );
  }
}

/// The portal backdrop: piano-keys image under a 30% black wash, with the
/// large centred logo watermark, exactly as the website's student/admin
/// pages.
class PortalBackground extends StatelessWidget {
  final Widget child;
  const PortalBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEE54B3), Color(0xFF5B8DEF)],
            ),
          ),
        ),
        Image.asset('images/harmonium_background.png', fit: BoxFit.cover),
        const ColoredBox(color: Color(0x4D000000)),
        Center(
          child: LayoutBuilder(
            builder: (context, c) {
              final size = (c.biggest.shortestSide * 0.9).clamp(0.0, 480.0);
              return Opacity(
                opacity: 0.9,
                child: Image.asset('images/logo.png', width: size, height: size, fit: BoxFit.contain),
              );
            },
          ),
        ),
        child,
      ],
    );
  }
}

/// The portal's translucent "glass" tile (dashboard, profile): terracotta /
/// red / green wash, blur, thin red border, white text.
class GlassTile extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Color iconColor;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const GlassTile({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.iconColor = Brand.orange,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Brand.cardRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            gradient: Brand.glassGradient,
            borderRadius: BorderRadius.circular(Brand.cardRadius),
            border: Border.all(color: const Color(0x4DDC2626)),
            boxShadow: Brand.cardShadow,
          ),
          child: DefaultTextStyle.merge(
            style: nunito(14, 400, color: Colors.white),
            child: IconTheme.merge(
              data: const IconThemeData(color: Colors.white),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Row(
                      children: [
                        if (icon != null) ...[
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: iconColor.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(icon, size: 20, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Text(
                            title!.toUpperCase(),
                            style: nunito(14, 500, color: Colors.white, spacing: 0.6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A white portal list card: rounded-lg, gray border, shadow-md, optional
/// gray-50 header strip.
class PortalCard extends StatelessWidget {
  final Widget child;
  final String? header;
  final EdgeInsetsGeometry padding;
  const PortalCard({
    super.key,
    required this.child,
    this.header,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Brand.radius),
        border: Border.all(color: Brand.gray200),
        boxShadow: Brand.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Brand.gray50,
                border: Border(bottom: BorderSide(color: Brand.gray200)),
              ),
              child: Text(header!, style: nunito(16, 600, color: Brand.gray900)),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Portal page title: 24–30px bold gray-300 with gray-200 subtitle.
class PageTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  const PageTitle(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: nunito(28, 700, color: Brand.gray300)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: nunito(15, 400, color: const Color(0xFFE5E7EB))),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

enum BadgeKind { purple, indigo, green, red, amber, gray }

/// Pill badge (Self-paced / Offline / payment-status style).
class StatusBadge extends StatelessWidget {
  final String label;
  final BadgeKind kind;
  final IconData? icon;
  const StatusBadge(this.label, {super.key, this.kind = BadgeKind.gray, this.icon});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (kind) {
      BadgeKind.purple => (const Color(0xFFF3E8FF), const Color(0xFF6B21A8)),
      BadgeKind.indigo => (const Color(0xFFE0E7FF), const Color(0xFF3730A3)),
      BadgeKind.green => (const Color(0xFFDCFCE7), const Color(0xFF166534)),
      BadgeKind.red => (const Color(0xFFFEE2E2), const Color(0xFF991B1B)),
      BadgeKind.amber => (const Color(0xFFFEF3C7), const Color(0xFF92400E)),
      BadgeKind.gray => (const Color(0xFFF3F4F6), const Color(0xFF1F2937)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Brand.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Text(label, style: nunito(12, 500, color: fg)),
        ],
      ),
    );
  }
}

/// Six-box one-time-code entry (matches the website's OTP screen): one
/// hidden text field does the real input (so paste and OS autofill work) and
/// six boxes display it. Fires [onCompleted] as soon as all digits are in.
class OtpCodeField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onCompleted;
  final int length;

  const OtpCodeField({
    super.key,
    required this.controller,
    this.onCompleted,
    this.length = 6,
  });

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _focus.dispose();
    super.dispose();
  }

  void _onChange() {
    setState(() {});
    final text = widget.controller.text;
    if (text.length == widget.length) widget.onCompleted?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focus.requestFocus(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(widget.length, (i) {
              final active = _focus.hasFocus && i == text.length.clamp(0, widget.length - 1);
              return Container(
                width: 46,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(Brand.radius),
                  border: Border.all(
                    color: active ? Brand.purpleLight : Brand.gray300,
                    width: 2,
                  ),
                ),
                child: Text(
                  i < text.length ? text[i] : '',
                  style: nunito(24, 700, color: Brand.gray900),
                ),
              );
            }),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: widget.length,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                showCursor: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A password field with the website's show/hide eye toggle.
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.hint,
    this.validator,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      validator: widget.validator,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      autofillHints: const [AutofillHints.password],
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: Brand.gray400),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

/// Width at which the shell switches from the phone layout (top/bottom bars)
/// to the desktop layout (side rail).
const double kWideBreakpoint = 768;

/// Standard scrolling body for a portal page: centred, max ~1100px wide, page
/// title on wide layouts (phones show it in the top bar), optional pull to
/// refresh.
class PortalScroll extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  const PortalScroll({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= kWideBreakpoint;
      final list = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 16, vertical: 16),
        children: [
          if (wide) PageTitle(title, subtitle: subtitle),
          for (final w in children) ...[w, const SizedBox(height: 16)],
        ],
      );
      final body = onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list);
      return Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: body),
      );
    });
  }
}

/// Full-screen portal page for routes pushed on top of the shell (e.g. the
/// admin panel): navy top bar with back button and orange title, over the
/// piano-keys background.
class PortalPage extends StatelessWidget {
  final String title;
  final Widget child;
  const PortalPage({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.navy,
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: Brand.chromeGradient,
              border: Border(bottom: BorderSide(color: Color(0x4DDC2626))),
            ),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 64,
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    if (Navigator.of(context).canPop())
                      IconButton(
                        tooltip: 'Back',
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).maybePop(),
                      )
                    else
                      const SizedBox(width: 12),
                    Text(title, style: nunito(18, 600, color: Brand.orange)),
                    const Spacer(),
                    Image.asset('images/logo.png', height: 44),
                    const SizedBox(width: 16),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: PortalBackground(child: child)),
        ],
      ),
    );
  }
}
