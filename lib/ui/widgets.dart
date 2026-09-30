import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';

/// Primary CTA: blue → violet neon gradient with a glow, brighter on hover,
/// spinner while working.
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
            style: sora(14, 700, color: Colors.white, spacing: 0.3),
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
          opacity: widget.onPressed == null && !widget.loading ? 0.45 : 1,
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                gradient: _hover && enabled ? Brand.primaryGradientHover : Brand.primaryGradient,
                borderRadius: radius,
                boxShadow: Brand.glow(Brand.blue, _hover && enabled ? 1.2 : 0.8),
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

/// Text painted with a gradient (headlines, the wordmark).
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Gradient gradient;
  final TextAlign? textAlign;

  const GradientText(
    this.text, {
    super.key,
    required this.style,
    this.gradient = Brand.textGradient,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(Offset.zero & bounds.size),
      child: Text(text, textAlign: textAlign, style: style.copyWith(color: Colors.white)),
    );
  }
}

/// The app's mark on dark backgrounds: a glowing waveform badge and the
/// gradient "Vasis Beats" wordmark. (The Vasis Studio logo has dark navy
/// lettering that disappears on this theme.)
class BrandMark extends StatelessWidget {
  final double size;
  final bool showWordmark;
  final bool vertical;

  const BrandMark({super.key, this.size = 36, this.showWordmark = true, this.vertical = false});

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Brand.cyan, Brand.blue, Brand.violet],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: Brand.glow(Brand.violet, 0.9),
      ),
      child: Icon(Icons.graphic_eq_rounded, color: Colors.white, size: size * 0.62),
    );
    if (!showWordmark) return badge;
    final word = GradientText('Vasis Beats', style: sora(size * (vertical ? 0.8 : 0.58), 800, spacing: -0.5));
    return vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: [badge, SizedBox(height: size * 0.3), word])
        : Row(mainAxisSize: MainAxisSize.min, children: [badge, SizedBox(width: size * 0.3), word]);
  }
}

/// Sign in / register / password screens: neon backdrop, slim bar with the
/// brand mark, centred card.
class AuthShell extends StatelessWidget {
  final Widget child;
  const AuthShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.bg,
      body: NeonBackground(
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Align(alignment: Alignment.centerLeft, child: BrandMark(size: 34)),
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
      ),
    );
  }
}

/// The rounded auth card: dark glass with a gradient neon rim (sign in /
/// register) or a plain border (password screens).
class AuthCard extends StatelessWidget {
  final Widget child;
  final bool plain;
  const AuthCard({super.key, required this.child, this.plain = false});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Brand.authCardRadius);
    final inner = Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Brand.surfaceRaised.withValues(alpha: 0.92), Brand.surface.withValues(alpha: 0.92)],
        ),
        borderRadius: plain ? radius : BorderRadius.circular(Brand.authCardRadius - 1.5),
        border: plain ? Border.all(color: Brand.border) : null,
      ),
      child: child,
    );
    if (plain) {
      return DecoratedBox(decoration: BoxDecoration(borderRadius: radius, boxShadow: Brand.cardShadow), child: inner);
    }
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Brand.cyan, Brand.violetDeep, Brand.pink],
        ),
        borderRadius: radius,
        boxShadow: [...Brand.glow(Brand.violet, 0.8), ...Brand.cardShadow],
      ),
      child: inner,
    );
  }
}

/// Title block used at the top of auth cards: brand mark (or icon badge),
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
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: Brand.primaryGradient,
              boxShadow: Brand.glow(Brand.blue),
            ),
            child: Icon(badgeIcon, color: Colors.white, size: 30),
          )
        else
          const BrandMark(size: 64, showWordmark: false),
        const SizedBox(height: 18),
        Text(title, textAlign: TextAlign.center, style: sora(26, 700, color: Brand.text, spacing: -0.3)),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, textAlign: TextAlign.center, style: nunito(15, 400, color: Brand.textMuted)),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

enum NoticeKind { error, success }

/// Error / success banner for forms and empty states.
class NoticeBanner extends StatelessWidget {
  final String message;
  final NoticeKind kind;
  const NoticeBanner(this.message, {super.key, this.kind = NoticeKind.error});

  @override
  Widget build(BuildContext context) {
    final color = kind == NoticeKind.error ? Brand.error : Brand.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(Brand.radius),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: nunito(14, 600, color: kind == NoticeKind.error ? Brand.errorText : Brand.successText),
      ),
    );
  }
}

/// The app backdrop: deep indigo with a faint grid and soft violet / blue /
/// pink glows that drift slowly. The drift stops when the OS asks for
/// reduced motion, and (via TickerMode) on tabs that aren't visible.
class NeonBackground extends StatefulWidget {
  final Widget child;
  const NeonBackground({super.key, required this.child});

  @override
  State<NeonBackground> createState() => _NeonBackgroundState();
}

class _NeonBackgroundState extends State<NeonBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _drift =
      AnimationController(vsync: this, duration: const Duration(seconds: 30));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0D0729), Brand.bg, Color(0xFF0A0520)],
            ),
          ),
        ),
        RepaintBoundary(child: CustomPaint(painter: _GlowPainter(_drift))),
        const RepaintBoundary(child: CustomPaint(painter: _GridPainter())),
        widget.child,
      ],
    );
  }
}

class _GlowPainter extends CustomPainter {
  final Animation<double> t;
  _GlowPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final a = t.value * 2 * math.pi;
    final r = size.shortestSide;
    void glow(Offset c, double radius, Color color) {
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: radius)),
      );
    }

    glow(Offset(size.width * (0.15 + 0.08 * math.sin(a)), size.height * (0.12 + 0.05 * math.cos(a))),
        r * 0.9, Brand.violetDeep.withValues(alpha: 0.28));
    glow(Offset(size.width * (0.9 + 0.06 * math.cos(a)), size.height * (0.75 + 0.06 * math.sin(a))),
        r * 0.85, Brand.blue.withValues(alpha: 0.2));
    glow(Offset(size.width * (0.55 + 0.1 * math.sin(a + 2)), size.height * (0.42 + 0.08 * math.cos(a + 1))),
        r * 0.55, Brand.pink.withValues(alpha: 0.08));
  }

  @override
  bool shouldRepaint(_GlowPainter old) => false;
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const step = 36.0;
    final paint = Paint()
      ..color = const Color(0x08FFFFFF)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

/// Dark glass panel with a neon rim and glow in [iconColor] (dashboard,
/// profile, player): optional uppercase title with a glowing icon chip.
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
    this.iconColor = Brand.violet,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.alphaBlend(iconColor.withValues(alpha: 0.1), Brand.surface), Brand.surface],
        ),
        borderRadius: BorderRadius.circular(Brand.cardRadius),
        border: Border.all(color: iconColor.withValues(alpha: 0.45), width: 1.2),
        boxShadow: Brand.glow(iconColor, 0.45),
      ),
      child: DefaultTextStyle.merge(
        style: nunito(14, 400, color: Brand.textSecondary),
        child: IconTheme.merge(
          data: const IconThemeData(color: Brand.text),
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
                          color: iconColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: iconColor.withValues(alpha: 0.5)),
                        ),
                        child: Icon(icon, size: 18, color: iconColor),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        title!.toUpperCase(),
                        style: sora(12, 700, color: Brand.text, spacing: 1.4),
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
    );
  }
}

/// A neutral glass list card: dark surface, subtle border, optional header
/// strip.
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
        color: Brand.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(Brand.cardRadius),
        border: Border.all(color: Brand.border),
        boxShadow: Brand.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: DefaultTextStyle.merge(
        style: nunito(14, 400, color: Brand.textSecondary),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Brand.surfaceRaised.withValues(alpha: 0.6),
                  border: const Border(bottom: BorderSide(color: Brand.border)),
                ),
                child: Text(header!.toUpperCase(), style: sora(12, 700, color: Brand.text, spacing: 1.4)),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// Page title: gradient Sora headline with a muted subtitle.
class PageTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  const PageTitle(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GradientText(title, style: sora(30, 800, spacing: -0.5)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: nunito(15, 500, color: Brand.textMuted)),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

enum BadgeKind { purple, indigo, green, red, amber, gray }

/// Pill badge (Supporters / Downloaded / role style): tinted fill, neon rim.
class StatusBadge extends StatelessWidget {
  final String label;
  final BadgeKind kind;
  final IconData? icon;
  const StatusBadge(this.label, {super.key, this.kind = BadgeKind.gray, this.icon});

  @override
  Widget build(BuildContext context) {
    final color = switch (kind) {
      BadgeKind.purple => Brand.violet,
      BadgeKind.indigo => Brand.blue,
      BadgeKind.green => Brand.green,
      BadgeKind.red => Brand.red,
      BadgeKind.amber => Brand.amber,
      BadgeKind.gray => Brand.textMuted,
    };
    final fg = Color.lerp(color, Colors.white, 0.35)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(Brand.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Text(label, style: sora(11, 600, color: fg, spacing: 0.2)),
        ],
      ),
    );
  }
}

/// A console pad (Practice screen): rounded square with a neon rim in
/// [color], a label, an optional value line and a status LED. [active]
/// lights it up; [breathing] adds a slow glow pulse (e.g. while playing).
class NeonPad extends StatefulWidget {
  final String label;
  final String? value;
  final IconData? icon;
  final Color color;
  final bool active;
  final bool breathing;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final double iconSize;

  const NeonPad({
    super.key,
    required this.label,
    required this.color,
    this.value,
    this.icon,
    this.active = false,
    this.breathing = false,
    this.onTap,
    this.semanticLabel,
    this.iconSize = 34,
  });

  @override
  State<NeonPad> createState() => _NeonPadState();
}

class _NeonPadState extends State<NeonPad> with SingleTickerProviderStateMixin {
  late final AnimationController _breath =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _syncBreath();
  }

  @override
  void didUpdateWidget(NeonPad old) {
    super.didUpdateWidget(old);
    _syncBreath();
  }

  void _syncBreath() {
    if (widget.breathing && !_breath.isAnimating) {
      _breath.repeat(reverse: true);
    } else if (!widget.breathing && _breath.isAnimating) {
      _breath.animateTo(0, duration: const Duration(milliseconds: 250));
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      toggled: widget.active,
      label: widget.semanticLabel ?? widget.label,
      value: widget.value,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1,
          duration: const Duration(milliseconds: 90),
          child: AnimatedBuilder(
            animation: _breath,
            builder: (context, child) {
              final pulse = reduceMotion ? 0.0 : _breath.value;
              final strength = (widget.active ? 0.9 : 0.35) + 0.6 * pulse + (_pressed ? 0.4 : 0);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Brand.cardRadius),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    // Opaque fills: a translucent one would let the glow
                    // shadow show through and wash the pad out.
                    colors: [
                      Color.alphaBlend(c.withValues(alpha: widget.active ? 0.26 : 0.1), Brand.surface),
                      Color.alphaBlend(c.withValues(alpha: widget.active ? 0.1 : 0.03), Brand.bg),
                    ],
                  ),
                  border: Border.all(color: c.withValues(alpha: widget.active ? 1 : 0.7), width: 2),
                  boxShadow: Brand.glow(c, strength),
                ),
                child: child,
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null)
                    Icon(widget.icon, size: widget.iconSize, color: Color.lerp(c, Colors.white, 0.25)),
                  if (widget.value != null)
                    FittedBox(
                      child: Text(widget.value!, style: sora(26, 800, color: Color.lerp(c, Colors.white, 0.25))),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    widget.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sora(12, 800, color: widget.active ? Color.lerp(c, Colors.white, 0.45) : c, spacing: 1.6),
                  ),
                  const SizedBox(height: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.active ? c : Brand.borderStrong,
                      boxShadow: widget.active ? Brand.glow(c, 0.6) : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Six-box one-time-code entry: one hidden text field does the real input
/// (so paste and OS autofill work) and six boxes display it. Fires
/// [onCompleted] as soon as all digits are in.
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
              final filled = i < text.length;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 46,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Brand.bg.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(Brand.radius),
                  border: Border.all(
                    color: active ? Brand.cyan : (filled ? Brand.violet : Brand.border),
                    width: active ? 2 : 1.5,
                  ),
                  boxShadow: active ? Brand.glow(Brand.cyan, 0.6) : null,
                ),
                child: Text(filled ? text[i] : '', style: sora(22, 700, color: Brand.text)),
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

/// A password field with a show/hide eye toggle.
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
              color: Brand.textMuted),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

/// Width at which the shell switches from the phone layout (top/bottom bars)
/// to the desktop layout (side rail).
const double kWideBreakpoint = 768;

/// Standard scrolling body for a page: centred, max ~1100px wide (or
/// [maxWidth]), page title on wide layouts (phones show it in the top bar),
/// optional pull to refresh.
class PortalScroll extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final double maxWidth;

  const PortalScroll({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.onRefresh,
    this.maxWidth = 1100,
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
      final body = onRefresh == null
          ? list
          : RefreshIndicator(
              color: Brand.cyan,
              backgroundColor: Brand.surfaceRaised,
              onRefresh: onRefresh!,
              child: list,
            );
      return Center(
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: body),
      );
    });
  }
}

/// Full-screen page for routes pushed on top of the shell (e.g. the admin
/// panel): dark glass top bar with back button and gradient title, over the
/// neon background.
class PortalPage extends StatelessWidget {
  final String title;
  final Widget child;
  const PortalPage({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.bg,
      body: NeonBackground(
        child: Column(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: Brand.chromeGradient,
                border: Border(bottom: BorderSide(color: Brand.border)),
              ),
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: 60,
                  child: Row(
                    children: [
                      const SizedBox(width: 4),
                      if (Navigator.of(context).canPop())
                        IconButton(
                          tooltip: 'Back',
                          icon: const Icon(Icons.arrow_back, color: Brand.text),
                          onPressed: () => Navigator.of(context).maybePop(),
                        )
                      else
                        const SizedBox(width: 12),
                      Expanded(child: GradientText(title, style: sora(18, 700))),
                      const BrandMark(size: 30, showWordmark: false),
                      const SizedBox(width: 16),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
