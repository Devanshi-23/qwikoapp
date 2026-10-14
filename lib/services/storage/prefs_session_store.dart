import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repositories/session_store.dart';

/// Saves the session in the device's key-value storage. Storage errors are
/// logged and ignored: they must never block signing in.
class PrefsSessionStore implements SessionStore {
  PrefsSessionStore({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  static const key = 'qwiko.session';

  final SharedPreferencesAsync _prefs;

  @override
  Future<SavedSession?> read() async {
    try {
      final raw = await _prefs.getString(key);
      return raw == null ? null : SavedSession.fromJson(jsonDecode(raw));
    } on Object catch (error) {
      debugPrint('Could not read the saved session: $error');
      return null;
    }
  }

  @override
  Future<void> write(SavedSession session) async {
    try {
      await _prefs.setString(key, jsonEncode(session.toJson()));
    } on Object catch (error) {
      debugPrint('Could not save the session: $error');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _prefs.remove(key);
    } on Object catch (error) {
      debugPrint('Could not clear the saved session: $error');
    }
  }
}
