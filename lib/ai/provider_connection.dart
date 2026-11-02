import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_brains.dart';

enum ApiProvider { openai, grok, claude, gemini, elevenlabs, azure }

enum ConnectionResult {
  connected,
  missingKey,
  missingRegion,
  invalidRegion,
  badKey,
  forbidden,
  quota,
  offline,
  failed,
}

/// Read-only, authenticated requests. Never generate billable speech/chat or
/// expose response bodies (providers can echo credentials in error messages).
abstract final class ProviderConnection {
  static Future<ConnectionResult> check({
    required ApiProvider provider,
    required String apiKey,
    required http.Client client,
    String region = '',
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) return ConnectionResult.missingKey;
    final area = region.trim();
    if (provider == ApiProvider.azure) {
      if (area.isEmpty) return ConnectionResult.missingRegion;
      if (!RegExp(r'^[a-z][a-z0-9-]*$').hasMatch(area)) {
        return ConnectionResult.invalidRegion;
      }
    }
    final (url, headers, field) = switch (provider) {
      ApiProvider.openai => (
        'https://api.openai.com/v1/models',
        {'Authorization': 'Bearer $key'},
        'data',
      ),
      ApiProvider.grok => ('https://api.x.ai/v1/models', {'Authorization': 'Bearer $key'}, 'data'),
      ApiProvider.claude => (
        'https://api.anthropic.com/v1/models',
        {'x-api-key': key, 'anthropic-version': CloudBrains.claudeVersion},
        'data',
      ),
      ApiProvider.gemini => (
        'https://generativelanguage.googleapis.com/v1beta/models',
        {'x-goog-api-key': key},
        'models',
      ),
      ApiProvider.elevenlabs => (
        'https://api.elevenlabs.io/v2/voices?page_size=1',
        {'xi-api-key': key},
        'voices',
      ),
      ApiProvider.azure => (
        'https://$area.tts.speech.microsoft.com/cognitiveservices/voices/list',
        {'Ocp-Apim-Subscription-Key': key},
        '',
      ),
    };
    try {
      // Disable redirects so credentials cannot follow a redirect to another host.
      final response = await (() async {
        final request = http.Request('GET', Uri.parse(url))
          ..followRedirects = false
          ..headers.addAll(headers);
        return http.Response.fromStream(await client.send(request));
      })().timeout(timeout);
      if (response.statusCode == 401) return ConnectionResult.badKey;
      if (response.statusCode == 403) return ConnectionResult.forbidden;
      if (response.statusCode == 402 || response.statusCode == 429) {
        return ConnectionResult.quota;
      }
      if (response.statusCode != 200) return ConnectionResult.failed;
      final data = jsonDecode(response.body);
      final valid = field.isEmpty ? data is List : data is Map && data[field] is List;
      return valid ? ConnectionResult.connected : ConnectionResult.failed;
    } on FormatException {
      return ConnectionResult.failed;
    } on Object {
      return ConnectionResult.offline;
    }
  }
}
