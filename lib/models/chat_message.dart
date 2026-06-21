class ChatMessage {
  final String id;
  String text;
  final bool isUser;
  final DateTime time;
  bool pending;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.time,
    this.pending = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'isUser': isUser,
        'time': time.toIso8601String(),
        'pending': pending,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        text: j['text'] as String,
        isUser: j['isUser'] as bool,
        time: DateTime.parse(j['time'] as String),
        pending: (j['pending'] as bool?) ?? false,
      );
}
