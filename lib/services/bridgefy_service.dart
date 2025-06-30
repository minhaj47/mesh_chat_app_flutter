import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:bridgefy/bridgefy.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_models.dart';

class BridgefyService {
  final Bridgefy _bridgefy = Bridgefy();
  BridgefyDelegate? _delegate;

  String _currentUserId = '';
  String get currentUserId => _currentUserId;

  Future<void> initialize(String apiKey, BridgefyDelegate delegate) async {
    _delegate = delegate;
    _currentUserId = const Uuid().v4();

    await _bridgefy.initialize(
      apiKey: apiKey,
      delegate: delegate,
      verboseLogging: false,
    );
  }

  Future<bool> get isInitialized async {
    try {
      return await _bridgefy.isInitialized;
    } catch (e) {
      log("Could not verify initialization status: $e");
      return true; // Assume success
    }
  }

  Future<void> start() async {
    await _bridgefy.start(
      userId: _currentUserId,
      propagationProfile: BridgefyPropagationProfile.standard,
    );
  }

  Future<void> stop() async {
    try {
      await _bridgefy.stop();
    } catch (e) {
      log("Failed to stop cleanly: $e");
    }
  }

  Future<List<String>> get connectedPeers async {
    try {
      return await _bridgefy.connectedPeers;
    } catch (e) {
      log("Failed to get connected peers: $e");
      return [];
    }
  }

  Future<void> sendMessage(ChatMessage message, String userName) async {
    final messagePayload = {
      'id': message.id,
      'content': message.content,
      'senderId': message.senderId,
      'senderName': userName,
      'timestamp': message.timestamp.millisecondsSinceEpoch,
    };

    final data = Uint8List.fromList(utf8.encode(jsonEncode(messagePayload)));

    await _bridgefy.send(
      data: data,
      transmissionMode: BridgefyTransmissionMode(
        type: BridgefyTransmissionModeType.broadcast,
        uuid: _currentUserId,
      ),
    );
  }

  static ChatMessage parseReceivedMessage(Uint8List data, String messageId) {
    try {
      final jsonString = utf8.decode(data);
      final messageData = jsonDecode(jsonString) as Map<String, dynamic>;

      return ChatMessage(
        id: messageData['id'] ?? messageId,
        content: messageData['content'] ?? 'Unknown message',
        senderId: messageData['senderId'] ?? 'Unknown',
        timestamp: messageData['timestamp'] != null
            ? DateTime.fromMillisecondsSinceEpoch(messageData['timestamp'])
            : DateTime.now(),
        isFromMe: false,
      );
    } catch (e) {
      // Fallback for non-JSON messages
      final content = utf8.decode(data);
      return ChatMessage(
        id: messageId,
        content: content,
        senderId: 'Unknown',
        timestamp: DateTime.now(),
        isFromMe: false,
      );
    }
  }
}
