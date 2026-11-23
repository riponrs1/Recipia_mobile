import 'package:flutter/material.dart';

/// Shared look for Sign in, Create account, Reset password and
/// "account set to be deleted" — matches the prototype.
const authBg = Color(0xFFFAF8F5);
const authSurface = Color(0xFFFFFFFF);
const authFg = Color(0xFF1E1916);
const authMuted = Color(0xFF6D625B);
const authLine = Color(0xFFEAE3D9);
const authAccent = Color(0xFFC84B31);
const authAccentSoft = Color(0xFFFCEEE9);
const authRed = Color(0xFFC0392B);
const authWarn = Color(0xFFA8650A);
const authWarnSoft = Color(0xFFFBEFD9);

final emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

class AuthScaffold extends StatelessWidget {
  final List<Widget> children;
  final bool showBack;
  final bool center;
  const AuthScaffold(
      {super.key, required this.children, this.showBack = false, this.center = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: authBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment:
                    center ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  if (showBack)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Semantics(
                        button: true,
                        label: 'Back',
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).maybePop(),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                                color: authSurface,
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(color: authLine)),
                            child: const Icon(Icons.chevron_left_rounded,
                                color: authFg),
                          ),
                        ),
                      ),
                    ),
                  if (showBack) const SizedBox(height: 28),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthTitle extends StatelessWidget {
  final String title;
  final Widget subtitle;
  final bool center;
  const AuthTitle(this.title, this.subtitle, {super.key, this.center = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(title,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: const TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.1,
                letterSpacing: -0.5,
                color: authFg)),
        const SizedBox(height: 6),
        DefaultTextStyle.merge(
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: const TextStyle(fontSize: 15, height: 1.5, color: authMuted),
          child: subtitle,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class AuthIcon extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final Color fg;
  const AuthIcon(this.icon,
      {super.key, this.bg = authAccentSoft, this.fg = authAccent});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 64,
          height: 64,
          margin: const EdgeInsets.only(bottom: 18),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
          child: Icon(icon, color: fg, size: 30),
        ),
      );
}

class AuthError extends StatelessWidget {
  final Widget child;
  const AuthError({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xFFFDECEA),
            borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFF9B2C22), size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: DefaultTextStyle.merge(
                style: const TextStyle(
                    fontSize: 14, height: 1.45, color: Color(0xFF9B2C22)),
                child: child),
          ),
        ]),
      );
}

/// Label + box + message under it; password boxes get a show/hide eye.
class AuthField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final String? error;
  final Widget? errorWidget;
  final bool password;
  final TextInputType? keyboard;
  final List<String>? autofill;
  final TextInputAction action;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmit;
  final Widget? below;
  const AuthField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    this.error,
    this.errorWidget,
    this.password = false,
    this.keyboard,
    this.autofill,
    this.action = TextInputAction.next,
    this.onChanged,
    this.onSubmit,
    this.below,
  });

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final bad = widget.error != null || widget.errorWidget != null;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w));
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 7),
          child: Text(widget.label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: authMuted)),
        ),
        TextField(
          controller: widget.controller,
          obscureText: widget.password && _hidden,
          keyboardType: widget.keyboard,
          autofillHints: widget.autofill,
          textInputAction: widget.action,
          autocorrect: !widget.password && widget.keyboard != TextInputType.emailAddress,
          enableSuggestions: !widget.password,
          onChanged: widget.onChanged,
          onSubmitted: (_) => widget.onSubmit?.call(),
          style: const TextStyle(fontSize: 16, color: authFg),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: const TextStyle(color: authMuted, fontSize: 16),
            filled: true,
            fillColor: authSurface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            enabledBorder: border(bad ? authRed : authLine),
            focusedBorder: border(bad ? authRed : authAccent, 1.5),
            suffixIcon: widget.password
                ? IconButton(
                    tooltip: _hidden ? 'Show password' : 'Hide password',
                    icon: Icon(
                        _hidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: _hidden ? authMuted : authAccent),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  )
                : null,
          ),
        ),
        if (widget.below != null) widget.below!,
        if (bad)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
            child: widget.errorWidget ??
                Text(widget.error!,
                    style: const TextStyle(fontSize: 12.5, color: authRed)),
          ),
      ]),
    );
  }
}

class AuthButton extends StatelessWidget {
  final String label;
  final String? busyLabel;
  final bool busy;
  final bool ghost;
  final VoidCallback? onTap;
  const AuthButton(this.label,
      {super.key, this.onTap, this.busy = false, this.busyLabel, this.ghost = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: busy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: ghost ? authSurface : authAccent,
          foregroundColor: ghost ? authFg : Colors.white,
          disabledBackgroundColor:
              ghost ? authSurface : authAccent.withOpacity(0.6),
          disabledForegroundColor: ghost ? authMuted : Colors.white,
          elevation: 0,
          side: ghost ? const BorderSide(color: authLine) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (busy) ...[
            SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: ghost ? authFg : Colors.white)),
            const SizedBox(width: 10),
          ],
          Text(busy ? (busyLabel ?? label) : label,
              style: const TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class AuthLink extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final double size;
  const AuthLink(this.text, this.onTap, {super.key, this.size = 14});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Text(text,
              style: TextStyle(
                  fontSize: size, fontWeight: FontWeight.w700, color: authAccent)),
        ),
      );
}
