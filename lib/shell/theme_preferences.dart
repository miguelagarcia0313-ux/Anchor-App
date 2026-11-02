import 'package:shared_preferences/shared_preferences.dart';

class ThemePreferences {
  const ThemePreferences({this._preferences});

  final SharedPreferences? _preferences;

  static const _darkModeKey = 'app.dark_mode';

  Future<bool> load() async {
    final preferences = _preferences ?? await SharedPreferences.getInstance();
    return preferences.getBool(_darkModeKey) ?? false;
  }

  Future<void> save(bool enabled) async {
    final preferences = _preferences ?? await SharedPreferences.getInstance();
    await preferences.setBool(_darkModeKey, enabled);
  }
}
