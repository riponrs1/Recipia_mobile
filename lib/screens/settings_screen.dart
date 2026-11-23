import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api_service.dart';
import '../app_settings.dart';
import 'login_screen.dart';

const _bg = Color(0xFFFAF8F5);
const _surface = Color(0xFFFFFFFF);
const _surface2 = Color(0xFFF4EFE8);
const _fg = Color(0xFF1E1916);
const _muted = Color(0xFF6D625B);
const _line = Color(0xFFEAE3D9);
const _accent = Color(0xFFC84B31);

const appVersion = '2.0.0 (1)';
const _site = 'https://recipia.bicitra.com';
const _red = Color(0xFFC0392B);

/// Settings page from the prototype: recipe defaults, money, about.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
              child: Row(children: [
                IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded, color: _fg),
                    onPressed: () => Navigator.pop(context)),
                const Text('Settings',
                    style: TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _fg)),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [
                  _blockTitle('Recipes'),
                  _label('Default unit'),
                  _segmented(),
                  const SizedBox(height: 6),
                  _switchRow(
                    'Show weight totals',
                    'Display total grams on recipe cards',
                    AppSettings.showWeights,
                    (v) async {
                      await AppSettings.setShowWeights(v);
                      setState(() {});
                    },
                  ),
                  _blockTitle('Money'),
                  _card([
                    _row('Currency', 'Used for prices and costs',
                        trailing: AppSettings.currency, onTap: _pickCurrency),
                  ]),
                  _blockTitle('About'),
                  _card([
                    _row('Help & feedback', 'Questions, bugs, ideas',
                        onTap: () => _open('$_site/help')),
                    _divider(),
                    _row('Privacy policy', 'What we store and why',
                        onTap: () => _open('$_site/privacy'), external: true),
                    _divider(),
                    _row('Terms of use', null,
                        onTap: () => _open('$_site/terms'), external: true),
                    _divider(),
                    _row('Version', null, trailing: appVersion),
                  ]),
                  _blockTitle('Account'),
                  _card([
                    _row('Delete account', 'Permanently remove your account and all recipes',
                        onTap: _deleteAccount, danger: true),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blockTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: _muted)),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 7, left: 2),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: _muted)),
      );

  Widget _segmented() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _surface2,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: AppSettings.units.entries.map((e) {
          final on = AppSettings.defaultUnit == e.key;
          return Expanded(
            child: Semantics(
              button: true,
              selected: on,
              label: 'Default unit ${e.value}',
              child: GestureDetector(
                onTap: () async {
                  await AppSettings.setDefaultUnit(e.key);
                  setState(() {});
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? _accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(e.value,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: on ? Colors.white : _muted)),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _switchRow(
      String title, String sub, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: _fg)),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(fontSize: 12, color: _muted)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.white,
          activeTrackColor: _accent,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: _line,
          trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        ),
      ]),
    );
  }

  Widget _card(List<Widget> rows) => Container(
        decoration: BoxDecoration(
          color: _surface,
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: rows),
      );

  Widget _divider() => const Divider(height: 1, color: _line);

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating, content: Text('Couldn’t open $url')));
    }
  }

  String _fmtDate(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  /// 30-day grace period: logged out now, deleted for good on the date.
  Future<void> _deleteAccount() async {
    final end = _fmtDate(DateTime.now().add(const Duration(days: 30)));
    final typed = TextEditingController();
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final ok = typed.text.trim().toUpperCase() == 'DELETE';
        Widget step(Color dot, bool filled, String title, String body) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 4, right: 12),
                  decoration: BoxDecoration(
                      color: filled ? dot : _bg,
                      shape: BoxShape.circle,
                      border: Border.all(color: dot, width: 2)),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700, color: _fg)),
                    const SizedBox(height: 2),
                    Text(body,
                        style: const TextStyle(fontSize: 13, height: 1.4, color: _muted)),
                  ]),
                ),
              ]),
            );
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, 14 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Delete your account?',
                      style: TextStyle(
                          fontFamily: 'SpaceGrotesk', fontSize: 18, fontWeight: FontWeight.w700, color: _fg)),
                  InkWell(
                    onTap: () => Navigator.pop(ctx, false),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _line),
                      ),
                      child: const Icon(Icons.close_rounded, size: 16, color: _muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _line)),
                child: Column(children: [
                  step(_accent, true, 'Today',
                      'You’re logged out on all phones. Your recipes are hidden, not deleted.'),
                  const Divider(height: 1, color: _line),
                  step(_accent, false, 'Next 30 days',
                      'Changed your mind? Just log in and tap Keep my account — everything comes back.'),
                  const Divider(height: 1, color: _line),
                  step(_red, true, end,
                      'Your account, recipes, ingredients, prices and photos are deleted for good.'),
                ]),
              ),
              const SizedBox(height: 14),
              const Text('Type DELETE to confirm',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _muted)),
              const SizedBox(height: 7),
              TextField(
                controller: typed,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setS(() {}),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: _surface,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: _line)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: _accent)),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: ok ? () => Navigator.pop(ctx, true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _red,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _red.withOpacity(0.4),
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Delete in 30 days',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _fg,
                    backgroundColor: _surface,
                    side: const BorderSide(color: _line),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
        );
      }),
    );
    typed.dispose();
    if (go != true || !mounted) return;
    try {
      final date = await ApiService().requestAccountDeletion();
      if (!mounted) return;
      final d = DateTime.tryParse(date);
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Account will be deleted on ${d == null ? date : _fmtDate(d)}'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _red,
        content: Text('Couldn’t reach the server. Try again when you’re online.'),
      ));
    }
  }

  Widget _row(String title, String? sub,
      {String? trailing, VoidCallback? onTap, bool external = false, bool danger = false}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: danger ? _red : _fg)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub,
                      style: const TextStyle(fontSize: 12, color: _muted)),
                ],
              ],
            ),
          ),
          if (trailing != null)
            Text(trailing,
                style: const TextStyle(fontSize: 14, color: _muted)),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(external ? Icons.north_east_rounded : Icons.chevron_right_rounded,
                color: _muted, size: external ? 17 : 20),
          ],
        ]),
      ),
    );
  }

  void _pickCurrency() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Currency',
                      style: TextStyle(
                          fontFamily: 'SpaceGrotesk',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _fg)),
                  InkWell(
                    onTap: () => Navigator.pop(ctx),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _surface2,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _line),
                      ),
                      child: const Icon(Icons.close_rounded, size: 16, color: _muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...AppSettings.currencies.entries.map((e) {
                final on = AppSettings.currency == e.value;
                return InkWell(
                  onTap: () async {
                    await AppSettings.setCurrency(e.value);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (mounted) setState(() {});
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Row(children: [
                      Expanded(
                        child: Text(e.key,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight:
                                    on ? FontWeight.w700 : FontWeight.w500,
                                color: on ? _accent : _fg)),
                      ),
                      if (on)
                        const Icon(Icons.check_rounded,
                            color: _accent, size: 20),
                    ]),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
