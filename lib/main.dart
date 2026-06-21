import 'package:flutter/material.dart';

import 'screens/connect_screen.dart';
import 'screens/chat_screen.dart';
import 'services/mqtt_service.dart';

void main() => runApp(const PankiApp());

const kBrand = Color(0xFF2F80ED);

class PankiApp extends StatefulWidget {
  const PankiApp({super.key});

  @override
  State<PankiApp> createState() => _PankiAppState();
}

class _PankiAppState extends State<PankiApp> {
  final MqttService mqtt = MqttService();
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    mqtt.loadSaved();
  }

  @override
  void dispose() {
    mqtt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Panki Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: kBrand,
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          centerTitle: true,
          elevation: 0.5,
        ),
      ),
      home: ListenableBuilder(
        listenable: mqtt,
        builder: (context, _) {
          return Scaffold(
            appBar: AppBar(
              title: Text(_tab == 0 ? 'Panki — Connect' : 'Assistant Chatbot'),
              actions: [
                if (_tab == 1)
                  IconButton(
                    tooltip: 'Clear history',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: mqtt.messages.isEmpty ? null : mqtt.clearHistory,
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(Icons.circle,
                      size: 12,
                      color: mqtt.isConnected ? Colors.green : Colors.grey),
                ),
              ],
            ),
            body: IndexedStack(
              index: _tab,
              children: [
                ConnectScreen(
                    mqtt: mqtt, onConnected: () => setState(() => _tab = 1)),
                ChatScreen(mqtt: mqtt),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.settings_ethernet), label: 'Connect'),
                NavigationDestination(
                    icon: Icon(Icons.chat_bubble_outline), label: 'Chatbot'),
              ],
            ),
          );
        },
      ),
    );
  }
}
