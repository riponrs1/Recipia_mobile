import 'package:flutter/foundation.dart';

/// Fired when the user taps the bottom tab they are already on.
/// Each tab's main screen listens and goes back to its start:
/// filters cleared, search cleared, scrolled to the top.
class TabReselect extends ChangeNotifier {
  TabReselect._();
  static final TabReselect instance = TabReselect._();

  int tab = -1;

  void fire(int index) {
    tab = index;
    notifyListeners();
  }
}

/// Ask the main screen to switch to a tab (0 recipes, 1 ingredients, 2 profile)
/// and show that tab from its start.
final ValueNotifier<int?> tabRequest = ValueNotifier(null);
