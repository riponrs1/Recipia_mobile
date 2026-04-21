import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../sync_provider.dart';
import '../api_service.dart';
import 'forgot_password_screen.dart';
import 'main_screen.dart';
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
  bool _obscurePassword = true;
  bool _rememberMe = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('remembered_email');
    if (savedEmail != null && savedEmail.isNotEmpty) {
      setState(() {
        _emailController.text = savedEmail;
        _rememberMe = true;
      });
    }
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final error = await _apiService.login(
      _emailController.text,
      _passwordController.text,
    );

    if (error == null) {
      // Save or Clear Email based on Remember Me
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('remembered_email', _emailController.text);
      } else {
        await prefs.remove('remembered_email');
      }

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = error;
      });
    }
  }

  Future<void> _enterOfflineMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_offline', true);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color antiqueCream = Color(0xFFFDFBF7);
    const Color mahogany = Color(0xFF5D4037);
    const Color softPeach = Color(0xFFFAB1A0);

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
                  // Atelier Logo Branding
                  Container(
                    height: 100,
                    width: 100,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
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
                  const SizedBox(height: 32),
                  const Text(
                    'RECIPIA',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: mahogany,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    'Your Personal Culinary Atelier',
                    style: TextStyle(
                      fontSize: 14,
                      color: mahogany.withOpacity(0.5),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 60),
                  
                  // Login Form
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('EMAIL ADDRESS'),
                      TextField(
                        controller: _emailController,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        decoration: _inputDecoration(Icons.email_outlined, 'e.g. chef@atelier.com'),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 24),
                      _buildLabel('PASSWORD'),
                      TextField(
                        controller: _passwordController,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        decoration: _inputDecoration(
                          Icons.lock_outline_rounded,
                          '••••••••',
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
                    ],
                  ),

                  // Remember & Forgot
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value: _rememberMe,
                              onChanged: (v) => setState(() => _rememberMe = v ?? false),
                              activeColor: mahogany,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Remember Me",
                            style: TextStyle(color: mahogany.withOpacity(0.6), fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(color: softPeach, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 48),
                  
                  // Buttons
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator(color: mahogany))
                        : ElevatedButton(
                            onPressed: _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: mahogany,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            child: const Text(
                              'Enter Atelier',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Guest / Offline Mode
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: OutlinedButton.icon(
                      onPressed: _enterOfflineMode,
                      icon: const Icon(Icons.offline_bolt_rounded, size: 20),
                      label: const Text(
                        'Continue as Guest (Offline)',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: mahogany.withOpacity(0.7),
                        side: BorderSide(color: mahogany.withOpacity(0.15), width: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                  
                  // Register
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'New to Recipia? ',
                        style: TextStyle(color: mahogany.withOpacity(0.5), fontSize: 14),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                        child: const Text(
                          'Create Account',
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
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: const Color(0xFF5D4037).withOpacity(0.4),
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(IconData icon, String hint, {Widget? suffixIcon}) {
    const Color mahogany = Color(0xFF5D4037);
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: mahogany.withOpacity(0.3), size: 20),
      suffixIcon: suffixIcon,
      hintStyle: TextStyle(color: mahogany.withOpacity(0.2), fontWeight: FontWeight.w500),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: mahogany.withOpacity(0.05)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: mahogany, width: 2),
      ),
    );
  }
}
