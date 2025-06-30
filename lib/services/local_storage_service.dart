import 'dart:convert';

import 'package:bridgefy_mesh_app/models/chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class LocalStorageService {
  static const String _keyPermissionsGranted = 'permissions_granted';
  static const String _keyUserName = 'user_name';
  static const String _keyUserId = 'user_id';
  static const String _keyMessages = 'chat_messages';
  static const String _keyLastInitTime = 'last_init_time';
  static const String _keySystemMessages = 'system_messages';
  static const String _keySDKInitialized = 'sdk_initialized';
  static const String _keySDKVersion = 'sdk_version';
  static const String _keyAppVersion = 'app_version';

  static SharedPreferences? _prefs;

  static Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // Permission management
  static Future<void> savePermissionStatus(bool granted) async {
    await _prefs?.setBool(_keyPermissionsGranted, granted);
  }

  static bool getPermissionStatus() {
    return _prefs?.getBool(_keyPermissionsGranted) ?? false;
  }

  // User info management
  static Future<void> saveUserInfo(String userId, String userName) async {
    await _prefs?.setString(_keyUserId, userId);
    await _prefs?.setString(_keyUserName, userName);
  }

  static Map<String, String> getUserInfo() {
    final userId = _prefs?.getString(_keyUserId);
    final userName = _prefs?.getString(_keyUserName);

    if (userId != null && userName != null) {
      return {'userId': userId, 'userName': userName};
    }

    // Generate new user info if not found
    final newUserId = const Uuid().v4();
    final newUserName = 'User_${newUserId.substring(0, 6)}';
    return {'userId': newUserId, 'userName': newUserName};
  }

  // Messages management
  static Future<void> saveMessages(List<ChatMessage> messages) async {
    final messagesJson = messages.map((msg) => msg.toJson()).toList();
    await _prefs?.setString(_keyMessages, jsonEncode(messagesJson));
  }

  static List<ChatMessage> getMessages() {
    final messagesStr = _prefs?.getString(_keyMessages);
    if (messagesStr == null) return [];

    try {
      final messagesList = jsonDecode(messagesStr) as List;
      return messagesList.map((json) => ChatMessage.fromJson(json)).toList();
    } catch (e) {
      print('Error loading messages: $e');
      return [];
    }
  }

  // System messages management
  static Future<void> saveSystemMessages(List<String> messages) async {
    await _prefs?.setStringList(_keySystemMessages, messages);
  }

  static List<String> getSystemMessages() {
    return _prefs?.getStringList(_keySystemMessages) ?? [];
  }

  // Enhanced SDK initialization tracking
  static Future<void> saveSDKInitialized(bool initialized,
      {String? version, String? appVersion}) async {
    await _prefs?.setBool(_keySDKInitialized, initialized);
    await _prefs?.setInt(
        _keyLastInitTime, DateTime.now().millisecondsSinceEpoch);

    if (version != null) {
      await _prefs?.setString(_keySDKVersion, version);
    }
    if (appVersion != null) {
      await _prefs?.setString(_keyAppVersion, appVersion);
    }
  }

  static bool wasSDKInitialized() {
    return _prefs?.getBool(_keySDKInitialized) ?? false;
  }

  static bool shouldReinitializeSDK(
      {String? currentAppVersion, String? currentSDKVersion}) {
    final lastInit = _prefs?.getInt(_keyLastInitTime);
    final wasInitialized = _prefs?.getBool(_keySDKInitialized) ?? false;
    final savedAppVersion = _prefs?.getString(_keyAppVersion);
    final savedSDKVersion = _prefs?.getString(_keySDKVersion);

    // Force reinit if never initialized
    if (!wasInitialized || lastInit == null) {
      return true;
    }

    // Force reinit if app version changed
    if (currentAppVersion != null &&
        savedAppVersion != null &&
        currentAppVersion != savedAppVersion) {
      return true;
    }

    // Force reinit if SDK version changed
    if (currentSDKVersion != null &&
        savedSDKVersion != null &&
        currentSDKVersion != savedSDKVersion) {
      return true;
    }

    // Reinitialize if more than 24 hours have passed (increased from 1 hour)
    final timeDiff = DateTime.now().millisecondsSinceEpoch - lastInit;
    return timeDiff > (24 * 60 * 60 * 1000); // 24 hours in milliseconds
  }

  static DateTime? getLastInitTime() {
    final lastInit = _prefs?.getInt(_keyLastInitTime);
    return lastInit != null
        ? DateTime.fromMillisecondsSinceEpoch(lastInit)
        : null;
  }

  // Clear SDK initialization state (for troubleshooting)
  static Future<void> clearSDKState() async {
    await _prefs?.remove(_keySDKInitialized);
    await _prefs?.remove(_keyLastInitTime);
    await _prefs?.remove(_keySDKVersion);
    await _prefs?.remove(_keyAppVersion);
  }

  // Clear all data (for reset functionality)
  static Future<void> clearAll() async {
    await _prefs?.clear();
  }

  // Clear only messages (for new chat)
  static Future<void> clearMessages() async {
    await _prefs?.remove(_keyMessages);
    await _prefs?.remove(_keySystemMessages);
  }
}
