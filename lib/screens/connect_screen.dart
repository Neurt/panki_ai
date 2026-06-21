import 'package:flutter/material.dart';

import '../main.dart' show kBrand;
import '../services/mqtt_service.dart';

/// Mirrors the "ID" reference screen: logo, app name, a connection field, and a
/// Load/Connect button. Here the "id" is the broker address of the Pi node, or
/// a cloud MQTT broker (e.g. HiveMQ Cloud) when phone and Pi are on different
/// networks — in which case TLS + credentials are required.
class ConnectScreen extends StatefulWidget {
  final MqttService mqtt;
  final VoidCallback onConnected;
  const ConnectScreen(
      {super.key, required this.mqtt, required this.onConnected});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final TextEditingController _host =
      TextEditingController(text: widget.mqtt.host);
  late final TextEditingController _port =
      TextEditingController(text: widget.mqtt.port.toString());
  late final TextEditingController _user =
      TextEditingController(text: widget.mqtt.username);
  late final TextEditingController _pass =
      TextEditingController(text: widget.mqtt.password);

  late bool _secure = widget.mqtt.secure;
  bool _obscurePass = true;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  /// Cloud brokers listen on 8883 for TLS; default the toggle on when the user
  /// types that port (they can still override it).
  void _onPortChanged(String v) {
    final p = int.tryParse(v.trim());
    if (p == 8883 && !_secure) setState(() => _secure = true);
  }

  Future<void> _connect() async {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 1883;
    if (host.isEmpty) return;
    await widget.mqtt.connect(host, port,
        user: _user.text.trim(), pass: _pass.text, secure: _secure);
    if (widget.mqtt.isConnected && mounted) widget.onConnected();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mqtt;
    final connecting = m.state == ConnState.connecting;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          Container(
            height: 96,
            width: 96,
            decoration: BoxDecoration(
              color: kBrand.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.smart_toy_outlined, size: 52, color: kBrand),
          ),
          const SizedBox(height: 16),
          const Text('PANKI',
              style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 2)),
          const Text('BPOM Edge Assistant',
              style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 40),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Broker address (Pi LAN IP or cloud host)',
                style: TextStyle(color: Colors.black54)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _host,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'e.g. 192.168.1.23 or xxxx.s1.eu.hivemq.cloud',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            onChanged: _onPortChanged,
            decoration: const InputDecoration(
              labelText: 'Port (1883 plain · 8883 TLS)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use TLS (secure)'),
            subtitle: const Text('Required for cloud brokers'),
            value: _secure,
            onChanged: (v) => setState(() => _secure = v),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _user,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Username (optional)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: _obscurePass,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Password (optional)',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(
                    _obscurePass ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: connecting ? null : _connect,
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: connecting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(m.isConnected ? 'Reconnect' : 'Connect'),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.circle,
                  size: 11,
                  color: m.isConnected
                      ? Colors.green
                      : (m.state == ConnState.error
                          ? Colors.red
                          : Colors.grey)),
              const SizedBox(width: 6),
              Flexible(
                  child: Text(m.statusMessage,
                      style: const TextStyle(color: Colors.black54))),
            ],
          ),
          if (m.isConnected) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => widget.onConnected(),
              child: const Text('Go to chat →'),
            ),
          ],
        ],
      ),
    );
  }
}
