/// Represents a chat message in a conversation about a math problem
class ChatMessage {
  final String id;
  final String problemId;
  final String message;
  final bool isUser;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.problemId,
    required this.message,
    required this.isUser,
    required this.createdAt,
  });

  /// Create a copy of this message with updated fields
  ChatMessage copyWith({
    String? id,
    String? problemId,
    String? message,
    bool? isUser,
    DateTime? createdAt,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      problemId: problemId ?? this.problemId,
      message: message ?? this.message,
      isUser: isUser ?? this.isUser,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Convert to JSON for database storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'problemId': problemId,
      'message': message,
      'isUser': isUser ? 1 : 0,  // Convert boolean to integer for SQLite
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Create from JSON from database
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      problemId: json['problemId'],
      message: json['message'],
      isUser: json['isUser'] == 1,  // Convert integer back to boolean
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  @override
  String toString() {
    return 'ChatMessage(id: $id, problemId: $problemId, isUser: $isUser, message: ${message.substring(0, message.length > 50 ? 50 : message.length)}...)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatMessage &&
        other.id == id &&
        other.problemId == problemId &&
        other.message == message &&
        other.isUser == isUser &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        problemId.hashCode ^
        message.hashCode ^
        isUser.hashCode ^
        createdAt.hashCode;
  }
}
