import 'package:flutter/material.dart';
import '../screens/dashboard_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/recipe_list_screen.dart';
import '../screens/recipe_form_screen.dart';
import '../screens/login_screen.dart';
import '../api_service.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(
              color: Colors.orange,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.restaurant_menu, size: 48, color: Colors.white),
                  SizedBox(height: 10),
                  Text(
                    'RecipeVault',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Dashboard'),
            onTap: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const DashboardScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Profile'),
            onTap: () {
              Navigator.of(context).pushReplacement( // Use pushReplacement to behave like a sidebar nav
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.book),
            title: const Text('Recipes'),
            onTap: () {
                Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const RecipeListScreen()),
                );
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_circle),
            title: const Text('Create Recipe'),
            onTap: () {
                // For 'Create', maybe just push instead of replace? 
                // Web uses standard link, so replace handles "context switch".
                // But usually Create is a sub-task. 
                // I'll use push for Create so back button works easily.
                Navigator.pop(context); // Close drawer
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RecipeFormScreen()),
                );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () async {
                await ApiService().logout();
                if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                    );
                }
            },
          ),
        ],
      ),
    );
  }
}
