import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../ai/provider_connection.dart';
import '../i18n/strings.dart';
import '../i18n/strings_connection.dart';
import '../theme/tokens.dart';
import 'buttons.dart';

class ConnectionTest extends StatefulWidget {
  const ConnectionTest({
    super.key,
    required this.provider,
    required this.apiKey,
    required this.mode,
    this.region = '',
    this.createClient,
  });

  final ApiProvider provider;
  final String apiKey;
  final String region;
  final MindMode mode;
  final http.Client Function()? createClient;

  @override
  State<ConnectionTest> createState() => _ConnectionTestState();
}

class _ConnectionTestState extends State<ConnectionTest> {
  bool _busy = false;
  ConnectionResult? _result;
  http.Client? _client;
  int _generation = 0;

  @override
  void didUpdateWidget(ConnectionTest oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider ||
        oldWidget.apiKey != widget.apiKey ||
        oldWidget.region != widget.region) {
      _generation++;
      _client?.close();
      _client = null;
      _busy = false;
      _result = null;
    }
  }

  @override
  void dispose() {
    _generation++;
    _client?.close();
    super.dispose();
  }

  Future<void> _check() async {
    if (_busy) return;
    final generation = ++_generation;
    final client = widget.createClient?.call() ?? http.Client();
    _client = client;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final result = await ProviderConnection.check(
        provider: widget.provider,
        apiKey: widget.apiKey,
        region: widget.region,
        client: client,
      );
      if (!mounted || generation != _generation) return;
      setState(() => _result = result);
    } finally {
      client.close();
      if (identical(_client, client)) _client = null;
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MindButton(
          label: _busy ? t.connectionTesting : t.connectionTest,
          mode: widget.mode,
          icon: Icons.wifi_tethering_rounded,
          onTap: _busy ? null : _check,
        ),
        if (_result != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              t.connectionResult(_result!),
              key: const ValueKey('connection-result'),
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: _result == ConnectionResult.connected
                    ? const Color(0xFF007E70)
                    : const Color(0xFFB46A00),
              ),
            ),
          ),
      ],
    );
  }
}
