import 'package:flutter/material.dart';
import '../api_service.dart';
import 'auth_widgets.dart';
import 'main_screen.dart';
import 'verify_email_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;
  Map<String, String> _errors = {};
  bool _emailTaken = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _longEnough => _passwordController.text.length >= 8;
  bool get _hasMix =>
      RegExp(r'[A-Za-z]').hasMatch(_passwordController.text) &&
      RegExp(r'\d').hasMatch(_passwordController.text);

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final a = _passwordController.text, b = _confirmPasswordController.text;
    final e = <String, String>{};
    if (name.isEmpty) e['name'] = 'Enter your name';
    if (email.isEmpty) {
      e['email'] = 'Enter your email';
    } else if (!emailRe.hasMatch(email)) {
      e['email'] = 'That doesn’t look like an email address';
    }
    if (a.length < 8) e['password'] = 'Use at least 8 characters';
    if (b.isEmpty) {
      e['confirm'] = 'Type the password again';
    } else if (a != b) {
      e['confirm'] = 'The passwords don’t match';
    }
    setState(() {
      _errors = e;
      _emailTaken = false;
    });
    if (e.isNotEmpty) return;

    setState(() => _isLoading = true);
    final result = await _apiService.registerAccount(name, email, a, b);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (result == null) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainScreen()), (_) => false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Welcome to Recipia, ${name.split(' ').first}'),
      ));
      return;
    }
    if (result['_verify'] == 'true') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => VerifyEmailScreen(email: email)),
      );
      return;
    }
    setState(() {
      _errors = {
        if (result['name'] != null) 'name': result['name']!,
        if (result['email'] != null) 'email': result['email']!,
        if (result['password'] != null) 'password': result['password']!,
        if (result['_'] != null) '_': result['_']!,
      };
      _emailTaken = (result['email'] ?? '').toLowerCase().contains('taken');
    });
  }

  Widget _rule(String text, bool ok) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Text('${ok ? '✓' : '○'} $text',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: ok ? FontWeight.w600 : FontWeight.w400,
                color: ok ? authAccent : authMuted)),
      );

  @override
  Widget build(BuildContext context) {
    final pw = _passwordController.text;
    final score = pw.isEmpty
        ? 0
        : (_longEnough ? 1 : 0) + (_hasMix ? 1 : 0) + (pw.length >= 12 ? 1 : 0);
    final barColor = [authRed, const Color(0xFFE1A33B), const Color(0xFF7FB069),
        const Color(0xFF2F9E5E)][score];
    return AuthScaffold(
      showBack: true,
      children: [
        const AuthTitle('Create account', Text('Start your recipe collection. It’s free.')),
        if (_errors['_'] != null) AuthError(child: Text(_errors['_']!)),
        AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AuthField(
              label: 'Name',
              controller: _nameController,
              hint: 'Your name',
              error: _errors['name'],
              autofill: const [AutofillHints.name],
            ),
            AuthField(
              label: 'Email',
              controller: _emailController,
              hint: 'you@email.com',
              keyboard: TextInputType.emailAddress,
              autofill: const [AutofillHints.email],
              error: _emailTaken ? null : _errors['email'],
              errorWidget: _emailTaken
                  ? Wrap(children: [
                      const Text('This email already has an account. ',
                          style: TextStyle(fontSize: 12.5, color: authRed)),
                      GestureDetector(
                        onTap: () => Navigator.of(context).maybePop(),
                        child: const Text('Sign in instead',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: authAccent,
                                decoration: TextDecoration.underline)),
                      ),
                    ])
                  : null,
            ),
            AuthField(
              label: 'Password',
              controller: _passwordController,
              hint: 'At least 8 characters',
              password: true,
              autofill: const [AutofillHints.newPassword],
              error: _errors['password'],
              onChanged: (_) => setState(() {}),
              below: Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: LinearProgressIndicator(
                      value: pw.isEmpty ? 0 : (score / 3).clamp(0.15, 1.0),
                      minHeight: 5,
                      backgroundColor: const Color(0xFFF4EFE8),
                      valueColor: AlwaysStoppedAnimation(barColor),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    _rule('8+ characters', _longEnough),
                    _rule('Letters & numbers', _hasMix),
                  ]),
                ]),
              ),
            ),
            AuthField(
              label: 'Confirm password',
              controller: _confirmPasswordController,
              hint: 'Type it again',
              password: true,
              autofill: const [AutofillHints.newPassword],
              error: _errors['confirm'],
              action: TextInputAction.done,
              onSubmit: _register,
            ),
          ]),
        ),
        AuthButton('Create account',
            busy: _isLoading, busyLabel: 'Creating account…', onTap: _register),
        const SizedBox(height: 22),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('Already have an account? ',
              style: TextStyle(fontSize: 14, color: authMuted)),
          AuthLink('Sign in', () => Navigator.of(context).maybePop()),
        ]),
      ],
    );
  }
}
