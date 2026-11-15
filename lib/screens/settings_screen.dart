import 'package:flutter/material.dart';
import '../app_settings.dart';

const _bg = Color(0xFFFFFBF0);
const _surface = Color(0xFFFFFFFF);
const _surface2 = Color(0xFFFBF6E8);
const _fg = Color(0xFF2D3436);
const _muted = Color(0xFF636E72);
const _line = Color(0xFFECE3D1);
const _accent = Color(0xFF1B4D3E);

const appVersion = '2.0';

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
                    _row('Version', null, trailing: appVersion),
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

  Widget _row(String title, String? sub,
      {String? trailing, VoidCallback? onTap}) {
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
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: _fg)),
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
            const Icon(Icons.chevron_right_rounded, color: _muted, size: 20),
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
              const Text('Currency',
                  style: TextStyle(
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _fg)),
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
