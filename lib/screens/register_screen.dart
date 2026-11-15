import 'package:flutter/material.dart';
import '../api_service.dart';
import 'main_screen.dart';

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
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  Future<void> _register() async {
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'Passwords do not match';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final error = await _apiService.register(
      _nameController.text,
      _emailController.text,
      _passwordController.text,
      _confirmPasswordController.text,
    );

    setState(() {
      _isLoading = false;
    });

    if (error == null) {
      if (mounted) {
        // Assuming auto-login or redirect to Home
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      }
    } else {
      setState(() {
        _errorMessage = error;
      });
    }
  }

  @override
    Widget build(BuildContext context) {
    const Color antiqueCream = Color(0xFFFFFBF0);
    const Color mahogany = Color(0xFF1B4D3E);
    const Color softPeach = Color(0xFF1B4D3E);

    return Scaffold(
      backgroundColor: antiqueCream,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Container(
                    height: 80,
                    width: 80,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: mahogany.withOpacity(0.08),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Hero(
                      tag: 'app_logo',
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Create account',
                    style: TextStyle(fontFamily: 'SpaceGrotesk',
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: mahogany,
                      letterSpacing: -1,
                    ),
                  ),
                  const Text(
                    'Start your recipe collection.',
                    style: TextStyle(fontSize: 15, color: Color(0xFF636E72)),
                  ),
                  const SizedBox(height: 32),

                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Name'),
                      TextField(
                        controller: _nameController,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        decoration: _inputDecoration(Icons.person_outline_rounded, 'Your name'),
                      ),
                      const SizedBox(height: 20),
                      _buildLabel('Email'),
                      TextField(
                        controller: _emailController,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        decoration: _inputDecoration(Icons.email_outlined, 'you@email.com'),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 20),
                      _buildLabel('Password'),
                      TextField(
                        controller: _passwordController,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        decoration: _inputDecoration(
                          Icons.lock_outline_rounded,
                          'Choose a password',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                              color: softPeach,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        obscureText: _obscurePassword,
                      ),
                      const SizedBox(height: 20),
                      _buildLabel('Confirm password'),
                      TextField(
                        controller: _confirmPasswordController,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        decoration: _inputDecoration(
                          Icons.lock_reset_rounded,
                          'Type it again',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                              color: softPeach,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                          ),
                        ),
                        obscureText: _obscureConfirmPassword,
                      ),
                    ],
                  ),

                  const SizedBox(height: 48),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator(color: mahogany))
                        : ElevatedButton(
                            onPressed: _register,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: mahogany,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text(
                              'Sign up',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                            ),
                          ),
                  ),

                  const SizedBox(height: 32),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already a member? ',
                        style: TextStyle(color: mahogany.withOpacity(0.5), fontSize: 14),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Text(
                          'Sign in',
                          style: TextStyle(color: mahogany, fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 7),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF636E72),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(IconData icon, String hint, {Widget? suffixIcon}) {
    const Color accent = Color(0xFF1B4D3E);
    return InputDecoration(
      hintText: hint,
      suffixIcon: suffixIcon,
      hintStyle: const TextStyle(color: Color(0xFF636E72), fontWeight: FontWeight.w400),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFECE3D1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
    );
  }
}
