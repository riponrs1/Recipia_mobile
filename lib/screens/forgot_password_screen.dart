import 'dart:async';

import 'package:flutter/material.dart';
import '../api_service.dart';
import 'auth_widgets.dart';

/// Step 1: ask for the email. Step 2: "Check your email" — the new password
/// is chosen on the web page the email links to. One link per minute.
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _emailController = TextEditingController(text: widget.initialEmail);
  bool _isLoading = false;
  String? _error;
  bool _notFound = false;
  String? _sentTo;
  int _wait = 0;
  Timer? _timer;

  @override
  void dispose() {
    _emailController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _wait = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  Future<void> _send({bool again = false}) async {
    final email = again ? _sentTo! : _emailController.text.trim().toLowerCase();
    setState(() {
      _notFound = false;
      _error = email.isEmpty
          ? 'Enter your email'
          : (!emailRe.hasMatch(email) ? 'That doesn’t look like an email address' : null);
    });
    if (_error != null) return;
    setState(() => _isLoading = true);
    final problem = await ApiService().sendPasswordResetEmail(email);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (problem == null) {
      setState(() => _sentTo = email);
      _startTimer();
      if (again) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Reset link sent again')));
      }
      return;
    }
    setState(() {
      final p = problem.toLowerCase();
      if (p.contains("can't find") || p.contains('cannot find')) {
        _notFound = true;
      } else if (p.contains('wait') || p.contains('throttle')) {
        _error = 'Please wait a minute before asking again.';
      } else {
        _error = problem;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _sentTo == null ? _ask() : _sent();
  }

  Widget _ask() => AuthScaffold(showBack: true, children: [
        const AuthIcon(Icons.lock_reset_rounded),
        const AuthTitle(
            'Forgot password?',
            Text(
                'Enter the email you signed up with. We’ll send you a link to set a new password.')),
        AuthField(
          label: 'Email',
          controller: _emailController,
          hint: 'you@email.com',
          keyboard: TextInputType.emailAddress,
          autofill: const [AutofillHints.email],
          action: TextInputAction.done,
          onSubmit: _send,
          error: _notFound ? null : _error,
          errorWidget: _notFound
              ? const Text(
                  'No account uses this email. Check for a typo, or create an account.',
                  style: TextStyle(fontSize: 12.5, color: authRed))
              : null,
        ),
        AuthButton('Send reset link',
            busy: _isLoading, busyLabel: 'Sending…', onTap: _send),
        const SizedBox(height: 18),
        Center(child: AuthLink('Back to sign in', () => Navigator.of(context).maybePop())),
      ]);

  Widget _step(int n, Widget text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration:
                const BoxDecoration(color: authAccentSoft, shape: BoxShape.circle),
            child: Text('$n',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: authAccent)),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: DefaultTextStyle.merge(
                  style: const TextStyle(fontSize: 14, height: 1.45, color: authFg),
                  child: text)),
        ]),
      );

  Widget _sent() => AuthScaffold(showBack: true, children: [
        const AuthIcon(Icons.mark_email_unread_outlined,
            bg: authAccent, fg: Colors.white),
        AuthTitle(
            'Check your email',
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'We sent a reset link to '),
              TextSpan(
                  text: _sentTo,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: authFg)),
            ]))),
        Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
              color: authSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: authLine)),
          child: Column(children: [
            _step(
                1,
                const Text.rich(TextSpan(children: [
                  TextSpan(text: 'Open the email from '),
                  TextSpan(text: 'Recipia', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: '. Not there? Check '),
                  TextSpan(text: 'Spam', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: '.'),
                ]))),
            const Divider(height: 1, color: authLine),
            _step(
                2,
                const Text.rich(TextSpan(children: [
                  TextSpan(text: 'Tap '),
                  TextSpan(
                      text: 'Reset Password', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: '. It opens in your browser.'),
                ]))),
            const Divider(height: 1, color: authLine),
            _step(3, const Text('Choose a new password there.')),
            const Divider(height: 1, color: authLine),
            _step(4, const Text('Come back here and sign in.')),
          ]),
        ),
        AuthButton('Back to sign in', onTap: () => Navigator.of(context).maybePop()),
        const SizedBox(height: 10),
        AuthButton(_wait > 0 ? 'Resend link in ${_wait}s' : 'Resend link',
            ghost: true,
            busy: _isLoading,
            busyLabel: 'Sending…',
            onTap: _wait > 0 ? null : () => _send(again: true)),
        const SizedBox(height: 16),
        Center(
          child: AuthLink('Use a different email', () {
            _timer?.cancel();
            setState(() {
              _sentTo = null;
              _wait = 0;
            });
          }),
        ),
      ]);
}
