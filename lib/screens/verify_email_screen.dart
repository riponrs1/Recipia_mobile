import 'dart:async';

import 'package:flutter/material.dart';
import '../api_service.dart';
import 'auth_widgets.dart';

/// Shown right after registration when the server sends an email verification
/// link. Mirrors ForgotPasswordScreen's "Check your email" layout.
class VerifyEmailScreen extends StatefulWidget {
  final String email;
  const VerifyEmailScreen({super.key, required this.email});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _isLoading = false;
  int _wait = 60;
  Timer? _timer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
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

  Future<void> _resend() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final problem = await ApiService().resendVerificationEmail(widget.email);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (problem == null) {
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Verification link sent again'),
      ));
      return;
    }
    setState(() => _error = problem);
  }

  Widget _step(int n, Widget text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: authAccentSoft, shape: BoxShape.circle),
            child: Text('$n',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: authAccent)),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: DefaultTextStyle.merge(
                  style: const TextStyle(
                      fontSize: 14, height: 1.45, color: authFg),
                  child: text)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(showBack: true, children: [
      const AuthIcon(Icons.mark_email_unread_outlined,
          bg: authAccent, fg: Colors.white),
      AuthTitle(
          'Verify your email',
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'We sent a verification link to '),
            TextSpan(
                text: widget.email,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: authFg)),
          ]))),
      if (_error != null) AuthError(child: Text(_error!)),
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
                TextSpan(
                    text: 'Recipia',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: '. Not there? Check '),
                TextSpan(
                    text: 'Spam',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: '.'),
              ]))),
          const Divider(height: 1, color: authLine),
          _step(
              2,
              const Text.rich(TextSpan(children: [
                TextSpan(text: 'Tap '),
                TextSpan(
                    text: 'Verify Email Address',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: '. It opens in your browser.'),
              ]))),
          const Divider(height: 1, color: authLine),
          _step(3, const Text('Come back to the Recipia app and sign in.')),
        ]),
      ),
      AuthButton('Go to sign in',
          onTap: () => Navigator.of(context).popUntil((r) => r.isFirst)),
      const SizedBox(height: 10),
      AuthButton(_wait > 0 ? 'Resend link in ${_wait}s' : 'Resend link',
          ghost: true,
          busy: _isLoading,
          busyLabel: 'Sending…',
          onTap: _wait > 0 ? null : _resend),
    ]);
  }
}
