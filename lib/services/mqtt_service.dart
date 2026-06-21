import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';

enum ConnState { disconnected, connecting, connected, error }

/// Holds the MQTT connection and the chat history. The chatbot is request/response
/// over pub/sub: each question is published to [askTopic] with a correlation id,
/// and the matching answer arrives on [answerTopic] carrying the same id.
class MqttService extends ChangeNotifier {
  MqttServerClient? _client;
  ConnState state = ConnState.disconnected;
  String statusMessage = 'Not connected';

  final List<ChatMessage> messages = [];

  String host = '';
  int port = 1883;
  String username = '';
  String password = '';
  bool secure = false; // TLS — required by cloud brokers (HiveMQ Cloud, etc.)
  String askTopic = 'panki/ask';
  String answerTopic = 'panki/answer';

  final _uuid = const Uuid();
  // correlationId -> the pending bot placeholder waiting to be filled
  final Map<String, ChatMessage> _pending = {};

  bool get isConnected => state == ConnState.connected;

  Future<void> connect(String host, int port,
      {String user = '', String pass = '', bool secure = false}) async {
    this.host = host;
    this.port = port;
    username = user;
    password = pass;
    this.secure = secure;
    state = ConnState.connecting;
    statusMessage = 'Connecting to $host:$port…';
    notifyListeners();

    final clientId = 'panki_app_${_uuid.v4().substring(0, 8)}';
    final client = MqttServerClient.withPort(host, clientId, port);
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.logging(on: false);
    if (secure) {
      // Use the device's system trust store; cloud brokers present a
      // Let's Encrypt / public CA cert, so no custom cert needs bundling.
      client.secure = true;
      client.securityContext = SecurityContext.defaultContext;
    }
    client.onDisconnected = _onDisconnected;
    client.onConnected = () {
      state = ConnState.connected;
      statusMessage = 'Connected to $host';
      notifyListeners();
    };

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();
    if (user.isNotEmpty) connMess.authenticateAs(user, pass);
    client.connectionMessage = connMess;

    try {
      await client.connect(
          user.isNotEmpty ? user : null, pass.isNotEmpty ? pass : null);
    } catch (e) {
      state = ConnState.error;
      statusMessage = 'Connection failed: $e';
      client.disconnect();
      notifyListeners();
      return;
    }

    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      _client = client;
      client.subscribe(answerTopic, MqttQos.atLeastOnce);
      client.updates?.listen(_onMessage);
      state = ConnState.connected;
      statusMessage = 'Connected to $host';
      await _persistBroker();
    } else {
      state = ConnState.error;
      statusMessage = 'Failed: ${client.connectionStatus}';
    }
    notifyListeners();
  }

  void disconnect() {
    _client?.disconnect();
    _client = null;
    state = ConnState.disconnected;
    statusMessage = 'Disconnected';
    notifyListeners();
  }

  void _onDisconnected() {
    if (state != ConnState.error) {
      state = ConnState.disconnected;
      statusMessage = 'Disconnected';
    }
    notifyListeners();
  }

  void sendQuestion(String text) {
    text = text.trim();
    if (text.isEmpty) return;
    if (!isConnected || _client == null) {
      statusMessage = 'Not connected — open the Connect tab first';
      notifyListeners();
      return;
    }

    final correlationId = _uuid.v4();
    messages.add(ChatMessage(
        id: _uuid.v4(), text: text, isUser: true, time: DateTime.now()));
    final placeholder = ChatMessage(
        id: correlationId,
        text: '',
        isUser: false,
        time: DateTime.now(),
        pending: true);
    messages.add(placeholder);
    _pending[correlationId] = placeholder;

    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode({'id': correlationId, 'message': text}));
    _client!.publishMessage(askTopic, MqttQos.atLeastOnce, builder.payload!);

    _persistHistory();
    notifyListeners();
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final e in events) {
      final msg = e.payload as MqttPublishMessage;
      final payload =
          MqttPublishPayload.bytesToStringAsString(msg.payload.message);
      try {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        final id = data['id'] as String?;
        final answer =
            (data['answer'] ?? data['explanation'] ?? '').toString();
        if (id != null && _pending.containsKey(id)) {
          final m = _pending.remove(id)!;
          m.text = answer.isEmpty ? '(empty response)' : answer;
          m.pending = false;
          _persistHistory();
          notifyListeners();
        }
      } catch (_) {
        // ignore malformed payloads
      }
    }
  }

  // ---- persistence -------------------------------------------------------

  Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    host = prefs.getString('host') ?? '';
    port = prefs.getInt('port') ?? 1883;
    username = prefs.getString('username') ?? '';
    password = prefs.getString('password') ?? '';
    secure = prefs.getBool('secure') ?? false;
    final raw = prefs.getString('history');
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List)
            .map((j) => ChatMessage.fromJson(j as Map<String, dynamic>))
            .toList();
        messages
          ..clear()
          ..addAll(list);
        for (final m in messages) {
          if (m.pending) m.pending = false; // clear stale "thinking" states
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _persistBroker() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host', host);
    await prefs.setInt('port', port);
    await prefs.setString('username', username);
    await prefs.setString('password', password);
    await prefs.setBool('secure', secure);
  }

  Future<void> _persistHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'history', jsonEncode(messages.map((m) => m.toJson()).toList()));
  }

  void clearHistory() {
    messages.clear();
    _pending.clear();
    _persistHistory();
    notifyListeners();
  }

  @override
  void dispose() {
    _client?.disconnect();
    super.dispose();
  }
}
