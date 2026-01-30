import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dashboard_screen.dart';
import 'recipe_list_screen.dart';
import 'profile_screen.dart';
import 'ingredients_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final _navigatorKeys = [
    GlobalKey<NavigatorState>(),
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
      // Pop to root if tapping the same tab
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use PopScope for Android 14+ predictive back support
    return PopScope(
      canPop: false, // We manually handle the back gesture
      onPopInvoked: (didPop) async {
        if (didPop) return;

        // Try to pop the nested navigator
        final NavigatorState? currentNavigator =
            _navigatorKeys[_currentIndex].currentState;

        if (currentNavigator != null && await currentNavigator.maybePop()) {
          // Nested navigator popped a route (e.g., Detail -> List)
          // We stay on the same screen (step-by-step)
          return;
        }

        // If at the root of the current tab...
        if (_currentIndex != 0) {
          // Go back to Home tab
          setState(() {
            _currentIndex = 0;
          });
        } else {
          // We are at Home (Dashboard) root. Exit the app.
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildNavigator(0, const DashboardScreen()),
            _buildNavigator(1, const RecipeListScreen()),
            _buildNavigator(2, const IngredientsScreen()),
            _buildNavigator(3, const ProfileScreen()),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          selectedItemColor: const Color(0xFFE74C3C),
          unselectedItemColor: Colors.grey,
          showUnselectedLabels: true,
          onTap: _onItemTapped,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book),
              label: 'Recipes',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.kitchen),
              label: 'Ingredients',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
