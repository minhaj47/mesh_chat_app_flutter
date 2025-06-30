// Enhanced chat_models.dart with JSON serialization support

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

enum MessageStatus {
  sending,
  sent,
  delivered,
  failed,
}

class ChatMessage {
  final String id;
  final String content;
  final String senderId;
  final DateTime timestamp;
  final bool isFromMe;
  final MessageStatus status;
  final String? senderName;

  const ChatMessage({
    required this.id,
    required this.content,
    required this.senderId,
    required this.timestamp,
    required this.isFromMe,
    this.status = MessageStatus.sent, // Default value from second code
    this.senderName,
  });

  // JSON serialization
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'senderId': senderId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isFromMe': isFromMe,
      'status': status.index,
      'senderName': senderName,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      content: json['content'] as String,
      senderId: json['senderId'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      isFromMe: json['isFromMe'] as bool,
      status: MessageStatus.values[json['status'] as int],
      senderName: json['senderName'] as String?,
    );
  }

  // Copy with method for updating message status
  ChatMessage copyWith({
    String? id,
    String? content,
    String? senderId,
    DateTime? timestamp,
    bool? isFromMe,
    MessageStatus? status,
    String? senderName,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      content: content ?? this.content,
      senderId: senderId ?? this.senderId,
      timestamp: timestamp ?? this.timestamp,
      isFromMe: isFromMe ?? this.isFromMe,
      status: status ?? this.status,
      senderName: senderName ?? this.senderName,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatMessage && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'ChatMessage(id: $id, content: $content, senderId: $senderId, timestamp: $timestamp, isFromMe: $isFromMe, status: $status, senderName: $senderName)';
  }
}

class ConnectedPeer {
  final String id;
  final String displayName;
  final DateTime connectedAt;
  final bool isSecureConnection;

  const ConnectedPeer({
    required this.id,
    required this.displayName,
    required this.connectedAt,
    this.isSecureConnection = false,
  });

  // JSON serialization for connected peers
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'connectedAt': connectedAt.millisecondsSinceEpoch,
      'isSecureConnection': isSecureConnection,
    };
  }

  factory ConnectedPeer.fromJson(Map<String, dynamic> json) {
    return ConnectedPeer(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      connectedAt:
          DateTime.fromMillisecondsSinceEpoch(json['connectedAt'] as int),
      isSecureConnection: json['isSecureConnection'] as bool? ?? false,
    );
  }

  ConnectedPeer copyWith({
    String? id,
    String? displayName,
    DateTime? connectedAt,
    bool? isSecureConnection,
  }) {
    return ConnectedPeer(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      connectedAt: connectedAt ?? this.connectedAt,
      isSecureConnection: isSecureConnection ?? this.isSecureConnection,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConnectedPeer && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'ConnectedPeer(id: $id, displayName: $displayName, connectedAt: $connectedAt, isSecureConnection: $isSecureConnection)';
  }
}
