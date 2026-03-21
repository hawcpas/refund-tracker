import 'package:shared_preferences/shared_preferences.dart';

class LocalAuthPrefs {
  static const _emailKey = 'last_login_email';
  static const _rememberMeKey = 'remember_me';

  /// Save email (used only if Remember Me is enabled)
  static Future<void> saveEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, email);
  }

  /// Get saved email (if any)
  static Future<String?> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey);
  }

  /// Clear saved email
  static Future<void> clearEmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
  }

  /// Save Remember Me preference
  static Future<void> setRememberMe(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberMeKey, value);
  }

  /// Get Remember Me preference
  /// Defaults to true (Intuit-style)
  static Future<bool> getRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberMeKey) ?? true;
  }
}