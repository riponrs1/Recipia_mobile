import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sync_provider.dart';
import 'perf.dart';
import 'app_settings.dart';
import 'screens/main_screen.dart';
import 'screens/login_screen.dart';
import 'screens/reactivate_screen.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyHttpOverrides();
  await AppSettings.load();
  watchSlowFrames();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SyncProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Recipia',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC84B31),
          primary: const Color(0xFFC84B31),
          secondary: const Color(0xFF6E2C1E),
          surface: const Color(0xFFFAF8F5),
          background: const Color(0xFFFAF8F5),
          onPrimary: Colors.white,
          onSurface: const Color(0xFF1E1916),
        ),
        scaffoldBackgroundColor: const Color(0xFFFAF8F5),
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontFamily: 'SpaceGrotesk',
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E1916),
              letterSpacing: -0.5),
          titleLarge: TextStyle(fontFamily: 'SpaceGrotesk',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E1916)),
          bodyLarge: TextStyle(fontSize: 16, color: Color(0xFF6D625B)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(fontFamily: 'SpaceGrotesk',
              color: Color(0xFF1E1916),
              fontSize: 20,
              fontWeight: FontWeight.bold),
          iconTheme: IconThemeData(color: Color(0xFF1E1916)),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: Colors.black.withOpacity(0.05)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFC84B31),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      home: const CheckAuth(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const MainScreen(),
      },
    );
  }
}

class CheckAuth extends StatefulWidget {
  const CheckAuth({super.key});

  @override
  State<CheckAuth> createState() => _CheckAuthState();
}

class _CheckAuthState extends State<CheckAuth> {
  bool _isLoading = true;
  bool _isLoggedIn = false;
  String? _deleteOn;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final isOffline = prefs.getBool('is_offline') ?? false;
    setState(() {
      _isLoggedIn = token != null || isOffline;
      _deleteOn = token != null ? prefs.getString('deletion_scheduled_for') : null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/logo.png', height: 80, width: 80),
              const SizedBox(height: 20),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }
    if (_isLoggedIn && _deleteOn != null) return ReactivateScreen(deleteOn: _deleteOn!);
    return _isLoggedIn ? const MainScreen() : const LoginScreen();
  }
}
