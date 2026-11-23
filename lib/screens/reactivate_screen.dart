import 'package:flutter/material.dart';
import '../api_service.dart';
import '../database_helper.dart';
import 'auth_widgets.dart';
import 'login_screen.dart';
import 'main_screen.dart';

/// Shown after signing in to an account that is waiting to be deleted.
/// "Keep my account" cancels the deletion; the other button signs out
/// and leaves it scheduled.
class ReactivateScreen extends StatefulWidget {
  final String deleteOn; // yyyy-mm-dd
  const ReactivateScreen({super.key, required this.deleteOn});

  @override
  State<ReactivateScreen> createState() => _ReactivateScreenState();
}

class _ReactivateScreenState extends State<ReactivateScreen> {
  bool _busy = false;
  String? _error;
  Map<String, dynamic> _stats = const {};

  @override
  void initState() {
    super.initState();
    ApiService().getRecipes().then((_) async {
      final s = await DatabaseHelper().getProfileStats();
      if (mounted) setState(() => _stats = s);
    }).catchError((_) {});
  }

  DateTime? get _date => DateTime.tryParse(widget.deleteOn);

  String get _dateText {
    final d = _date;
    if (d == null) return widget.deleteOn;
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  int get _daysLeft {
    final d = _date;
    if (d == null) return 0;
    final now = DateTime.now();
    return d.difference(DateTime(now.year, now.month, now.day)).inDays.clamp(0, 999);
  }

  Future<void> _keep() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ApiService().keepAccount();
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()), (_) => false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('Welcome back — your account won’t be deleted'),
    ));
  }

  Future<void> _leave() async {
    setState(() => _busy = true);
    await ApiService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('Still scheduled for $_dateText'),
    ));
  }

  Widget _row(String k, Object? v) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(fontSize: 14, color: authFg))),
          Text('${v ?? '–'}',
              style: const TextStyle(
                  fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w700, color: authFg)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final n = _daysLeft;
    return PopScope(
      canPop: false,
      child: AuthScaffold(center: true, children: [
        const AuthIcon(Icons.schedule_rounded, bg: authWarnSoft, fg: authWarn),
        AuthTitle(
            'Your account is set to be deleted',
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'On '),
              TextSpan(
                  text: _dateText,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: authFg)),
              const TextSpan(text: ' — '),
              TextSpan(
                  text: '$n day${n == 1 ? '' : 's'} left',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: authFg)),
              const TextSpan(text: '. Until then nothing is lost.'),
            ]))),
        if (_error != null) AuthError(child: Text(_error!)),
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
              color: authSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: authLine)),
          child: Column(children: [
            _row('Recipes', _stats['recipeCount']),
            const Divider(height: 1, color: authLine),
            _row('Ingredients & prices', _stats['ingredientCount']),
            const Divider(height: 1, color: authLine),
            _row('Sections', _stats['sectionCount']),
          ]),
        ),
        AuthButton('Keep my account', busy: _busy, busyLabel: 'Please wait…', onTap: _keep),
        const SizedBox(height: 10),
        AuthButton('No, keep it scheduled', ghost: true, onTap: _busy ? null : _leave),
        const SizedBox(height: 16),
        const Text(
            'You’ll be logged out. Log in again any time before the date to keep your account.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.45, color: authMuted)),
      ]),
    );
  }
}
