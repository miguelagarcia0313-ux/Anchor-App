import 'package:shared_preferences/shared_preferences.dart';

class ModulePreferences {
  const ModulePreferences({this._preferences});

  final SharedPreferences? _preferences;

  Future<Set<String>> load({
    required String userId,
    required Set<String> defaultModuleIds,
  }) async {
    final preferences = _preferences ?? await SharedPreferences.getInstance();
    final storedIds = preferences.getStringList(_keyFor(userId));
    if (storedIds == null) {
      return {...defaultModuleIds};
    }
    return storedIds.toSet().intersection(defaultModuleIds);
  }

  Future<void> save({
    required String userId,
    required Set<String> enabledModuleIds,
  }) async {
    final preferences = _preferences ?? await SharedPreferences.getInstance();
    await preferences.setStringList(_keyFor(userId), enabledModuleIds.toList());
  }

  String _keyFor(String userId) => 'dashboard.modules.$userId';
}
