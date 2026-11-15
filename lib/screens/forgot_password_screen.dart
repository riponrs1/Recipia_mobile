import 'package:flutter/material.dart';
import '../api_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _message;
  bool _isError = false;

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _message = 'Please enter your email.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    // Real API call
    try {
      final result = await ApiService().sendPasswordResetEmail(email);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _message = result ?? 'Reset link sent if account exists.';
          _isError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _message = e.toString().replaceAll('Exception: ', '');
          _isError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: _fg),
                      onPressed: () => Navigator.pop(context)),
                  const Text('Reset password',
                      style: TextStyle(fontFamily: 'SpaceGrotesk',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _fg)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                            color: _accentSoft,
                            borderRadius: BorderRadius.circular(26)),
                        child: const Icon(Icons.lock_reset_rounded,
                            color: _accent, size: 40),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Forgot your password?',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'SpaceGrotesk',
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: _fg),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter your email and we’ll send you a link to set a new one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: _muted, height: 1.4),
                    ),
                    const SizedBox(height: 26),
                    if (_message != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isError
                              ? const Color(0xFFFDEDEC)
                              : _accentSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: _isError
                                  ? const Color(0xFFC0392B)
                                  : _accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    const Text('Email',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _muted)),
                    const SizedBox(height: 7),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(fontSize: 15, color: _fg),
                      decoration: InputDecoration(
                        hintText: 'you@example.com',
                        prefixIcon:
                            const Icon(Icons.email_outlined, color: _muted),
                        filled: true,
                        fillColor: _surface,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: _line)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: _line)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: _accent, width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _resetPassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 3))
                            : const Text('Send reset link',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to sign in',
                          style: TextStyle(
                              color: _muted, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _bg = Color(0xFFFFFBF0);
const _surface = Color(0xFFFFFFFF);
const _fg = Color(0xFF2D3436);
const _muted = Color(0xFF636E72);
const _line = Color(0xFFECE3D1);
const _accent = Color(0xFF1B4D3E);
const _accentSoft = Color(0xFFE6EFE9);
