import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart' show kBrand;
import '../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleColor = isUser ? kBrand : Colors.white;
    final textColor = isUser ? Colors.white : Colors.black87;

    final bubble = Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isUser ? 16 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 16),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 1)),
        ],
      ),
      child: message.pending
          ? const _ThinkingDots()
          : SelectableText(message.text,
              style: TextStyle(color: textColor, height: 1.35)),
    );

    final avatar = CircleAvatar(
      radius: 16,
      backgroundColor: isUser ? kBrand.withValues(alpha: 0.15) : const Color(0xFFE0E3E8),
      child: Icon(isUser ? Icons.person : Icons.smart_toy_outlined,
          size: 18, color: isUser ? kBrand : Colors.black54),
    );

    final row = Row(
      mainAxisAlignment:
          isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: isUser
          ? [Flexible(child: bubble), const SizedBox(width: 8), avatar]
          : [avatar, const SizedBox(width: 8), Flexible(child: bubble)],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Column(
        crossAxisAlignment: align,
        children: [
          row,
          Padding(
            padding: EdgeInsets.only(
                top: 2, left: isUser ? 0 : 40, right: isUser ? 40 : 0),
            child: Text(DateFormat('HH:mm').format(message.time),
                style: const TextStyle(fontSize: 11, color: Colors.black38)),
          ),
        ],
      ),
    );
  }
}

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();
  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots> {
  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
            height: 14,
            width: 14,
            child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 10),
        Text('Panki is thinking…', style: TextStyle(color: Colors.black54)),
      ],
    );
  }
}
