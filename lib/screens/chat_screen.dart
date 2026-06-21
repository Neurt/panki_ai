import 'package:flutter/material.dart';

import '../main.dart' show kBrand;
import '../services/mqtt_service.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final MqttService mqtt;
  const ChatScreen({super.key, required this.mqtt});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.mqtt.addListener(_scrollToBottom);
  }

  @override
  void dispose() {
    widget.mqtt.removeListener(_scrollToBottom);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      }
    });
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    widget.mqtt.sendQuestion(text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mqtt;
    return Column(
      children: [
        if (!m.isConnected)
          Container(
            width: double.infinity,
            color: const Color(0xFFFDECEA),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: const Text('Not connected — open the Connect tab',
                style: TextStyle(color: Color(0xFFB3261E))),
          ),
        Expanded(
          child: m.messages.isEmpty
              ? const _EmptyState()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: m.messages.length,
                  itemBuilder: (_, i) => MessageBubble(message: m.messages[i]),
                ),
        ),
        _InputBar(controller: _input, onSend: _send, enabled: m.isConnected),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.smart_toy_outlined, size: 56, color: Colors.black26),
          SizedBox(height: 12),
          Text('Ask about a product to get its\nmandatory BPOM test parameters',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black45)),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;
  const _InputBar(
      {required this.controller, required this.onSend, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => enabled ? onSend() : null,
                decoration: InputDecoration(
                  hintText: 'Enter a product description…',
                  filled: true,
                  fillColor: const Color(0xFFF0F1F4),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            CircleAvatar(
              backgroundColor: enabled ? kBrand : Colors.grey,
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: enabled ? onSend : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
