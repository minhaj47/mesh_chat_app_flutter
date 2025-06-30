import 'dart:typed_data';

import 'package:bridgefy/bridgefy.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_models.dart';
import '../services/bridgefy_service.dart';
import '../services/local_storage_service.dart';
import '../services/permission_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/status_bar.dart';

class MeshChatPage extends StatefulWidget {
  @override
  _MeshChatPageState createState() => _MeshChatPageState();
}

class _MeshChatPageState extends State<MeshChatPage>
    implements BridgefyDelegate {
  final BridgefyService _bridgefyService = BridgefyService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // App state
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  bool _permissionsGranted = false;
  String _currentUserName = '';
  String _currentUserId = '';
  String _errorMessage = '';
  bool _isInitializing = false;
  String _appVersion = '';

  // Chat data
  final List<ChatMessage> _messages = [];
  final Map<String, ConnectedPeer> _connectedPeers = {};

  // UI state
  final List<String> _systemMessages = [];

  @override
  void initState() {
    super.initState();
    _initializeWithStorage();
  }

  Future<void> _initializeWithStorage() async {
    setState(() => _isInitializing = true);

    try {
      // Get app version for tracking
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = packageInfo.version;

      // Initialize local storage
      await LocalStorageService.initialize();

      // Load user info
      final userInfo = LocalStorageService.getUserInfo();
      _currentUserId = userInfo['userId']!;
      _currentUserName = userInfo['userName']!;

      // Save user info if it was newly generated
      await LocalStorageService.saveUserInfo(_currentUserId, _currentUserName);

      // Load previous messages and system messages
      final savedMessages = LocalStorageService.getMessages();
      final savedSystemMessages = LocalStorageService.getSystemMessages();

      setState(() {
        _messages.addAll(savedMessages);
        _systemMessages.addAll(savedSystemMessages);
      });

      _addSystemMessage("Loaded ${savedMessages.length} previous messages");

      // Check if we need to request permissions again
      _permissionsGranted = LocalStorageService.getPermissionStatus();

      if (!_permissionsGranted) {
        await _checkAndRequestPermissions();
      } else {
        _addSystemMessage("Using cached permission status");
        setState(() => _permissionsGranted = true);
      }

      // Initialize Bridgefy if permissions are granted
      if (_permissionsGranted) {
        await _initializeBridgefyWithCache();
      }
    } catch (e) {
      _setError("Initialization failed: $e");
    } finally {
      setState(() => _isInitializing = false);
    }

    // Scroll to bottom after loading messages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  Future<void> _checkAndRequestPermissions() async {
    _addSystemMessage("Checking permissions...");
    setState(() => _connectionStatus = ConnectionStatus.connecting);

    try {
      final granted = await PermissionService.checkAndRequestPermissions();

      setState(() {
        _permissionsGranted = granted;
        if (!granted) {
          _connectionStatus = ConnectionStatus.error;
          _errorMessage = "Required permissions not granted";
        }
      });

      // Save permission status to local storage
      await LocalStorageService.savePermissionStatus(granted);

      _addSystemMessage(granted
          ? "All permissions granted and saved"
          : "Some permissions denied - app may not work properly");
    } catch (e) {
      setState(() {
        _connectionStatus = ConnectionStatus.error;
        _errorMessage = "Permission check failed: $e";
        _permissionsGranted = false;
      });
      _addSystemMessage("Permission check failed: $e");
      await LocalStorageService.savePermissionStatus(false);
    }
  }

  Future<void> _initializeBridgefyWithCache() async {
    if (!_permissionsGranted) {
      _setError("Cannot initialize: Permissions not granted");
      return;
    }

    try {
      // Check if we need to reinitialize based on improved logic
      final shouldReinit = LocalStorageService.shouldReinitializeSDK(
        currentAppVersion: _appVersion,
        // You can add SDK version here if available
      );

      final wasSDKInitialized = LocalStorageService.wasSDKInitialized();
      final lastInitTime = LocalStorageService.getLastInitTime();

      if (wasSDKInitialized && !shouldReinit) {
        _addSystemMessage(
            "Using cached SDK initialization from ${lastInitTime?.toString().substring(0, 19) ?? 'unknown time'}");

        // Try to start directly without reinitializing
        setState(() => _connectionStatus = ConnectionStatus.connecting);

        try {
          await _startBridgefy();
          return; // Success - no need to reinitialize
        } catch (e) {
          _addSystemMessage(
              "Failed to start with cached initialization, will reinitialize: $e");
          // Fall through to reinitialization
        }
      }

      _addSystemMessage(
          "Initializing Bridgefy SDK... (Reason: ${!wasSDKInitialized ? 'Never initialized' : 'Reinit required'})");
      setState(() => _connectionStatus = ConnectionStatus.connecting);

      await _bridgefyService.initialize(
        "3b431d37-6394-4dad-8ce5-a1785cfd9a5c",
        this,
      );

      // Wait a bit for initialization to complete
      await Future.delayed(Duration(milliseconds: 1000));

      final isInitialized = await _bridgefyService.isInitialized;

      if (isInitialized) {
        _addSystemMessage("SDK initialized successfully");
        // Mark as initialized in storage
        await LocalStorageService.saveSDKInitialized(true,
            appVersion: _appVersion);
        await _startBridgefy();
      } else {
        _setError("SDK initialization failed - not marked as initialized");
        // Mark as failed
        await LocalStorageService.saveSDKInitialized(false,
            appVersion: _appVersion);
      }
    } catch (e) {
      _setError("Failed to initialize SDK: $e");
      // Mark as failed
      await LocalStorageService.saveSDKInitialized(false,
          appVersion: _appVersion);
    }
  }

  Future<void> _startBridgefy() async {
    try {
      _addSystemMessage("Starting mesh network...");
      await _bridgefyService.start();
    } catch (e) {
      _setError("Failed to start Bridgefy: $e");
      // If start fails, mark SDK as needing reinitialization
      await LocalStorageService.saveSDKInitialized(false,
          appVersion: _appVersion);
    }
  }

  Future<void> _sendMessage() async {
    if (_connectionStatus != ConnectionStatus.connected) {
      _showSnackBar("Not connected to mesh network");
      return;
    }

    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) {
      _showSnackBar("Please enter a message");
      return;
    }

    try {
      final chatMessage = ChatMessage(
        id: const Uuid().v4(),
        content: messageText,
        senderId: _currentUserId,
        timestamp: DateTime.now(),
        isFromMe: true,
        status: MessageStatus.sending,
      );

      setState(() {
        _messages.add(chatMessage);
      });
      _scrollToBottom();
      _messageController.clear();

      // Save messages to local storage
      await _saveMessagesToStorage();

      await _bridgefyService.sendMessage(chatMessage, _currentUserName);
    } catch (e) {
      _updateMessageStatus(messageText, MessageStatus.failed,
          content: messageText);
      _showSnackBar("Failed to send message: $e");
      await _saveMessagesToStorage(); // Save even failed messages
    }
  }

  Future<void> _saveMessagesToStorage() async {
    try {
      await LocalStorageService.saveMessages(_messages);
      await LocalStorageService.saveSystemMessages(_systemMessages);
    } catch (e) {
      debugPrint('Error saving messages: $e');
    }
  }

  void _updateMessageStatus(String messageId, MessageStatus status,
      {String? content}) {
    setState(() {
      final index = _messages.indexWhere((msg) =>
          (content != null && msg.content == content) || msg.id == messageId);
      if (index >= 0) {
        _messages[index] = _messages[index].copyWith(status: status);
      }
    });
    _saveMessagesToStorage(); // Save updated status
  }

  void _updateConnectedPeers() async {
    if (_connectionStatus != ConnectionStatus.connected) return;

    final peers = await _bridgefyService.connectedPeers;
    setState(() {
      // Remove disconnected peers
      _connectedPeers.removeWhere((id, peer) => !peers.contains(id));

      // Add new peers
      for (String peerId in peers) {
        if (!_connectedPeers.containsKey(peerId)) {
          _connectedPeers[peerId] = ConnectedPeer(
            id: peerId,
            displayName: 'User_${peerId.substring(0, 6)}',
            connectedAt: DateTime.now(),
          );
        }
      }
    });
  }

  void _addSystemMessage(String message) {
    final timestampedMessage =
        "${DateTime.now().toString().substring(11, 19)}: $message";
    setState(() {
      _systemMessages.add(timestampedMessage);
    });
    _saveMessagesToStorage(); // Save system messages
  }

  void _setError(String error) {
    setState(() {
      _connectionStatus = ConnectionStatus.error;
      _errorMessage = error;
    });
    _addSystemMessage("ERROR: $error");
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Permissions Required'),
        content: Text(
          'This app needs location and Bluetooth permissions to connect to nearby devices.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: Text('Open Settings'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _checkAndRequestPermissions();
            },
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _showSystemMessages() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('System Messages'),
        content: Container(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: _systemMessages.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  _systemMessages[index],
                  style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showOptionsMenu() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Options'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.refresh),
              title: Text('Reconnect'),
              onTap: () {
                Navigator.pop(context);
                _initializeBridgefyWithCache();
              },
            ),
            ListTile(
              leading: Icon(Icons.security),
              title: Text('Check Permissions'),
              onTap: () {
                Navigator.pop(context);
                _showPermissionDialog();
              },
            ),
            ListTile(
              leading: Icon(Icons.build),
              title: Text('Force Reinitialize SDK'),
              onTap: () async {
                Navigator.pop(context);
                await LocalStorageService.clearSDKState();
                _addSystemMessage("SDK state cleared - will reinitialize");
                await _initializeBridgefyWithCache();
              },
            ),
            ListTile(
              leading: Icon(Icons.clear_all),
              title: Text('Clear Chat'),
              onTap: () async {
                Navigator.pop(context);
                await LocalStorageService.clearMessages();
                setState(() {
                  _messages.clear();
                  _systemMessages.clear();
                });
                _addSystemMessage("Chat history cleared");
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_forever),
              title: Text('Reset App Data'),
              onTap: () async {
                Navigator.pop(context);
                await LocalStorageService.clearAll();
                setState(() {
                  _messages.clear();
                  _systemMessages.clear();
                  _connectedPeers.clear();
                  _permissionsGranted = false;
                  _connectionStatus = ConnectionStatus.disconnected;
                });
                _addSystemMessage("App data reset - restart required");
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mesh Chat'),
        actions: [
          // Connection status indicator
          Container(
            margin: EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isInitializing
                      ? Icons.hourglass_empty
                      : _connectionStatus == ConnectionStatus.connected
                          ? Icons.wifi
                          : _connectionStatus == ConnectionStatus.connecting
                              ? Icons.wifi_off
                              : Icons.error,
                  color: _isInitializing
                      ? Colors.blue
                      : _connectionStatus == ConnectionStatus.connected
                          ? Colors.green
                          : _connectionStatus == ConnectionStatus.connecting
                              ? Colors.orange
                              : Colors.red,
                ),
                SizedBox(width: 4),
                Text(
                  '${_connectedPeers.length}',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          // System messages button
          IconButton(
            icon: Icon(Icons.info_outline),
            onPressed: _showSystemMessages,
          ),
          // Options menu
          IconButton(
            icon: Icon(Icons.more_vert),
            onPressed: _showOptionsMenu,
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          StatusBar(
            connectionStatus: _connectionStatus,
            connectedPeersCount: _connectedPeers.length,
            currentUserName: _currentUserName,
            errorMessage: _errorMessage,
          ),

          // Chat messages
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isInitializing
                              ? Icons.hourglass_empty
                              : Icons.chat_bubble_outline,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        SizedBox(height: 16),
                        Text(
                          _isInitializing
                              ? 'Initializing...'
                              : 'No messages yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          _isInitializing
                              ? 'Loading your previous chats and connecting...'
                              : _connectionStatus == ConnectionStatus.connected
                                  ? 'Start chatting with nearby devices!'
                                  : 'Connect to the mesh network to start chatting',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return MessageBubble(message: _messages[index]);
                    },
                  ),
          ),

          // Message input
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: _isInitializing
                          ? 'Initializing...'
                          : _connectionStatus == ConnectionStatus.connected
                              ? 'Type a message...'
                              : 'Connect to send messages',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    enabled: !_isInitializing &&
                        _connectionStatus == ConnectionStatus.connected,
                    onSubmitted: (_) => _sendMessage(),
                    textInputAction: TextInputAction.send,
                  ),
                ),
                SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: !_isInitializing &&
                          _connectionStatus == ConnectionStatus.connected
                      ? _sendMessage
                      : null,
                  child: Icon(Icons.send),
                  mini: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // BridgefyDelegate implementation
  @override
  void bridgefyDidStart({required String currentUserID}) {
    setState(() {
      _connectionStatus = ConnectionStatus.connected;
      _errorMessage = '';
    });
    _addSystemMessage("Connected to mesh network");
    _updateConnectedPeers();
  }

  @override
  void bridgefyDidFailToStart({BridgefyError? error}) {
    _setError("Failed to start: ${error?.message ?? 'Unknown error'}");
    // Mark SDK as needing reinitialization on start failure
    LocalStorageService.saveSDKInitialized(false, appVersion: _appVersion);
  }

  @override
  void bridgefyDidStop() {
    setState(() {
      _connectionStatus = ConnectionStatus.disconnected;
      _connectedPeers.clear();
    });
    _addSystemMessage("Disconnected from mesh network");
  }

  @override
  void bridgefyDidFailToStop({BridgefyError? error}) {
    _addSystemMessage("Stop failed: ${error?.message ?? 'Unknown error'}");
  }

  @override
  void bridgefyDidConnect({required String userID}) {
    _addSystemMessage("Peer connected: ${userID.substring(0, 8)}");
    _updateConnectedPeers();
  }

  @override
  void bridgefyDidDisconnect({required String userID}) {
    setState(() {
      _connectedPeers.remove(userID);
    });
    _addSystemMessage("Peer disconnected: ${userID.substring(0, 8)}");
  }

  @override
  void bridgefyDidReceiveData({
    required Uint8List data,
    required String messageId,
    required BridgefyTransmissionMode transmissionMode,
  }) {
    final chatMessage = BridgefyService.parseReceivedMessage(data, messageId);

    setState(() {
      // Avoid duplicate messages
      if (!_messages.any((msg) => msg.id == chatMessage.id)) {
        _messages.add(chatMessage);
      }
    });
    _scrollToBottom();
    _saveMessagesToStorage(); // Save received messages
  }

  @override
  void bridgefyDidSendMessage({required String messageID}) {
    _updateMessageStatus(messageID, MessageStatus.sent);
  }

  @override
  void bridgefyDidFailSendingMessage({
    required String messageID,
    BridgefyError? error,
  }) {
    _updateMessageStatus(messageID, MessageStatus.failed);
    _showSnackBar("Message failed to send");
  }

  // Additional delegate methods with minimal implementation
  @override
  void bridgefyDidUpdateState({required String state}) {
    _addSystemMessage("State: $state");
  }

  @override
  void bridgefyDidDestroySession() {
    _addSystemMessage("Session destroyed");
  }

  @override
  void bridgefyDidEstablishSecureConnection({required String userID}) {
    _addSystemMessage("Secure connection: ${userID.substring(0, 8)}");
  }

  @override
  void bridgefyDidFailToDestroySession() {
    _addSystemMessage("Failed to destroy session");
  }

  @override
  void bridgefyDidFailToEstablishSecureConnection({
    required String userID,
    BridgefyError? error,
  }) {
    _addSystemMessage("Secure connection failed: ${userID.substring(0, 8)}");
  }

  @override
  void bridgefyDidReceiveDataFromUser({
    required Uint8List data,
    required String messageId,
    required String userID,
  }) {
    bridgefyDidReceiveData(
      data: data,
      messageId: messageId,
      transmissionMode: BridgefyTransmissionMode(
        type: BridgefyTransmissionModeType.p2p,
        uuid: userID,
      ),
    );
  }

  @override
  void bridgefyDidSendDataProgress({
    required String messageID,
    required int position,
    required int of,
  }) {
    // Optionally handle progress updates for large messages
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _bridgefyService.stop();
    super.dispose();
  }
}
