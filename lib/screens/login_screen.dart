import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import 'auth_widgets.dart';
import 'forgot_password_screen.dart';
import 'main_screen.dart';
import 'reactivate_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;
  bool _rememberMe = true;
  String? _emailError, _passwordError;
  bool _wrongDetails = false;
  String? _otherError;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('remembered_email');
    if (savedEmail != null && savedEmail.isNotEmpty && mounted) {
      setState(() {
        _emailController.text = savedEmail;
        _rememberMe = true;
      });
    }
  }

  Future<void> _login() async {
    final email = _emailController.text.trim().toLowerCase();
    final pass = _passwordController.text;
    setState(() {
      _emailError = email.isEmpty
          ? 'Enter your email'
          : (!emailRe.hasMatch(email) ? 'That doesn’t look like an email address' : null);
      _passwordError = pass.isEmpty ? 'Enter your password' : null;
      _wrongDetails = false;
      _otherError = null;
    });
    if (_emailError != null || _passwordError != null) return;

    setState(() => _isLoading = true);
    final error = await _apiService.login(email, pass);
    if (!mounted) return;

    if (error == null) {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('remembered_email', email);
      } else {
        await prefs.remove('remembered_email');
      }
      final scheduled = prefs.getString('deletion_scheduled_for');
      if (!mounted) return;
      setState(() => _isLoading = false);
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => scheduled != null
              ? ReactivateScreen(deleteOn: scheduled)
              : const MainScreen()));
      return;
    }
    setState(() {
      _isLoading = false;
      if (error.toLowerCase().contains('incorrect') ||
          error.toLowerCase().contains('credentials')) {
        _wrongDetails = true;
        _passwordController.clear();
      } else if (error.toLowerCase().contains('deleted')) {
        _otherError = 'This account has been deleted.';
      } else if (error.startsWith('Connection error')) {
        _otherError = 'No connection. Check your internet and try again.';
      } else {
        _otherError = error;
      }
    });
  }

  void _openForgot() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ForgotPasswordScreen(initialEmail: _emailController.text.trim())));

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      center: true,
      children: [
        Center(
          child: Container(
            width: 84,
            height: 84,
            margin: const EdgeInsets.only(bottom: 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: authLine),
              boxShadow: [
                BoxShadow(
                    color: authFg.withOpacity(0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8)),
              ],
            ),
            padding: const EdgeInsets.all(9),
            child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
          ),
        ),
        const AuthTitle('Welcome back', Text('Sign in to your Recipia kitchen.'),
            center: true),
        if (_wrongDetails)
          AuthError(
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('Email or password is wrong. Try again or '),
              GestureDetector(
                onTap: _openForgot,
                child: const Text('reset your password',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline)),
              ),
              const Text('.'),
            ]),
          ),
        if (_otherError != null) AuthError(child: Text(_otherError!)),
        AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AuthField(
              label: 'Email',
              controller: _emailController,
              hint: 'you@email.com',
              error: _emailError,
              keyboard: TextInputType.emailAddress,
              autofill: const [AutofillHints.email],
            ),
            AuthField(
              label: 'Password',
              controller: _passwordController,
              hint: 'Your password',
              error: _passwordError,
              password: true,
              autofill: const [AutofillHints.password],
              action: TextInputAction.done,
              onSubmit: _login,
            ),
          ]),
        ),
        Row(children: [
          Semantics(
            checked: _rememberMe,
            label: 'Remember me',
            child: InkWell(
              onTap: () => setState(() => _rememberMe = !_rememberMe),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _rememberMe ? authAccent : authSurface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: _rememberMe ? authAccent : authLine, width: 1.5),
                    ),
                    child: _rememberMe
                        ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 9),
                  const Text('Remember me',
                      style: TextStyle(fontSize: 14, color: authFg)),
                ]),
              ),
            ),
          ),
          const Spacer(),
          AuthLink('Forgot password?', _openForgot),
        ]),
        const SizedBox(height: 16),
        AuthButton('Sign in',
            busy: _isLoading, busyLabel: 'Signing in…', onTap: _login),
        const SizedBox(height: 22),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('New to Recipia? ',
              style: TextStyle(fontSize: 14, color: authMuted)),
          AuthLink(
              'Create account',
              () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RegisterScreen()))),
        ]),
      ],
    );
  }
}
