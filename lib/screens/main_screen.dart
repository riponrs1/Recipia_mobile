import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../sync_provider.dart';
import '../perf.dart';
import '../database_helper.dart';
import 'recipe_list_screen.dart';
import 'profile_screen.dart';
import 'ingredients_screen.dart';
import 'trash_screen.dart';
import '../services/price_book.dart';
import '../tab_events.dart';

const _bg = Color(0xFFFAF8F5);
const _surface = Color(0xFFFFFFFF);
const _line = Color(0xFFEAE3D9);
const _accent = Color(0xFFC84B31);
const _muted = Color(0xFF6D625B);

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _hasInitialSyncRun = false;

  @override
  void initState() {
    super.initState();
    tabRequest.addListener(_onTabRequest);
    _triggerBackgroundSync();
  }

  @override
  void dispose() {
    tabRequest.removeListener(_onTabRequest);
    super.dispose();
  }

  /// Another screen (e.g. the profile counts) asked to open a tab.
  void _onTabRequest() {
    final i = tabRequest.value;
    if (i == null || !mounted) return;
    tabRequest.value = null;
    _navigatorKeys[i].currentState?.popUntil((route) => route.isFirst);
    setState(() => _currentIndex = i);
    TabReselect.instance.fire(i); // start of the list, filters cleared
  }

  Future<void> _triggerBackgroundSync() async {
    if (_hasInitialSyncRun) return;
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      final syncProvider = Provider.of<SyncProvider>(context, listen: false);
      final isNewInstall = await syncProvider.detectMissingLocalData();
      if (isNewInstall) {
        await syncProvider.downloadAllFromServer();
      }
      if (!mounted) return;
      setState(() => _hasInitialSyncRun = true);
      // one-time tidy-up after the old auto-add bug (cheap when there's nothing to do)
      await DatabaseHelper().dedupeIngredients().catchError((_) => 0);
      // recipes in Trash for more than 30 days are deleted for good
      purgeOldTrash().catchError((_) => 0);
      // one price list: make sure every recipe ingredient is in Ingredients
      final report = await perfAsync('startup ingredients check', () => PriceBook.instance.migrateIfNeeded());
      if (mounted && report != null && report.firstRun && report.added > 0) {
        _showUpdateSummary(report);
      }
    }
  }

  void _goIngredients(String? filter) {
    setState(() => _currentIndex = 1);
    ingredientFilterRequest.value = filter;
  }

  /// Shown once, after the switch to one shared price list.
  void _showUpdateSummary(MigrationReport r) {
    Widget row(IconData icon, Color color, String text, String? action, VoidCallback? onTap) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.35, color: Color(0xFF1E1916)))),
            if (action != null)
              TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(foregroundColor: _accent, visualDensity: VisualDensity.compact),
                child: Text(action, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ]),
        );
    const warn = Color(0xFFA8650A);
    showModalBottomSheet(
      context: context,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ingredients updated',
                style: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1E1916))),
            const SizedBox(height: 4),
            const Text('Ingredients is now one price list for all recipes. Costs are the same as before.',
                style: TextStyle(fontSize: 13, color: _muted, height: 1.4)),
            const SizedBox(height: 10),
            row(Icons.check_circle_rounded, _accent,
                '${r.added} ingredient${r.added == 1 ? '' : 's'} added from your ${r.recipes} recipe${r.recipes == 1 ? '' : 's'}', null, null),
            if (r.differentPrices.isNotEmpty)
              row(Icons.info_outline_rounded, warn,
                  '${r.differentPrices.length} had different prices in different recipes — those recipes keep their own price', null, null),
            if (r.duplicates > 0)
              row(Icons.warning_amber_rounded, warn, '${r.duplicates} look like duplicates', 'Review', () {
                Navigator.pop(ctx);
                _goIngredients(null);
              }),
            if (r.noPrice > 0)
              row(Icons.warning_amber_rounded, warn, '${r.noPrice} have no price yet', 'Add prices', () {
                Navigator.pop(ctx);
                _goIngredients('Needs price');
              }),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent, foregroundColor: Colors.white, elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  final _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  Widget _buildNavigator(int index, Widget child) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (routeSettings) {
        return MaterialPageRoute(builder: (_) => child);
      },
    );
  }

  void _onItemTapped(int index) {
    if (_currentIndex == index) {
      // tapping the tab you're on: back to its main screen, filters cleared
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
      FocusManager.instance.primaryFocus?.unfocus();
      TabReselect.instance.fire(index);
    } else {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final NavigatorState? currentNavigator =
            _navigatorKeys[_currentIndex].currentState;
        if (currentNavigator != null && await currentNavigator.maybePop()) {
          return;
        }
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildNavigator(0, const RecipeListScreen()),
            _buildNavigator(1, const IngredientsScreen()),
            _buildNavigator(2, const ProfileScreen()),
          ],
        ),
        bottomNavigationBar: _buildNavBar(),
      ),
    );
  }

  Widget _buildNavBar() {
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            children: [
              _navItem(0, Icons.receipt_long_rounded, 'Recipes'),
              _navItem(1, Icons.restaurant_rounded, 'Ingredients'),
              _navItem(2, Icons.person_outline_rounded, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final on = _currentIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onItemTapped(index),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 23, color: on ? _accent : _muted),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: on ? _accent : _muted)),
          ],
        ),
      ),
    );
  }
}
