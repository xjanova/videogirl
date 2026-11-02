import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videogirl/ai/provider_connection.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_connection.dart';
import 'package:videogirl/theme/tokens.dart';
import 'package:videogirl/widgets/connection_test.dart';

void main() {
  for (final provider in ApiProvider.values) {
    test('${provider.name} uses the authenticated read-only endpoint', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.followRedirects, isFalse);
        expect(request.url.scheme, 'https');
        expect(request.url.toString(), isNot(contains('test-secret')));
        expect(request.body, isEmpty);
        final (host, path, header, value, body) = switch (provider) {
          ApiProvider.openai => (
            'api.openai.com',
            '/v1/models',
            'Authorization',
            'Bearer test-secret',
            {'data': []},
          ),
          ApiProvider.grok => (
            'api.x.ai',
            '/v1/models',
            'Authorization',
            'Bearer test-secret',
            {'data': []},
          ),
          ApiProvider.claude => (
            'api.anthropic.com',
            '/v1/models',
            'x-api-key',
            'test-secret',
            {'data': []},
          ),
          ApiProvider.gemini => (
            'generativelanguage.googleapis.com',
            '/v1beta/models',
            'x-goog-api-key',
            'test-secret',
            {'models': []},
          ),
          ApiProvider.elevenlabs => (
            'api.elevenlabs.io',
            '/v2/voices',
            'xi-api-key',
            'test-secret',
            {'voices': []},
          ),
          ApiProvider.azure => (
            'southeastasia.tts.speech.microsoft.com',
            '/cognitiveservices/voices/list',
            'Ocp-Apim-Subscription-Key',
            'test-secret',
            [],
          ),
        };
        expect(request.url.host, host);
        expect(request.url.path, path);
        expect(request.headers[header], value);
        return http.Response(jsonEncode(body), 200);
      });
      addTearDown(client.close);
      expect(
        await ProviderConnection.check(
          provider: provider,
          apiKey: ' test-secret ',
          region: 'southeastasia',
          client: client,
        ),
        ConnectionResult.connected,
      );
    });
  }

  test('missing credentials or invalid Azure region send no request', () async {
    final client = MockClient((_) async => throw StateError('must not send'));
    addTearDown(client.close);
    for (final (key, region, expected) in [
      ('', 'eastasia', ConnectionResult.missingKey),
      ('key', '', ConnectionResult.missingRegion),
      ('key', 'eastasia.example.com/path', ConnectionResult.invalidRegion),
    ]) {
      expect(
        await ProviderConnection.check(
          provider: ApiProvider.azure,
          apiKey: key,
          region: region,
          client: client,
        ),
        expected,
      );
    }
  });

  for (final (status, expected) in [
    (401, ConnectionResult.badKey),
    (403, ConnectionResult.forbidden),
    (402, ConnectionResult.quota),
    (429, ConnectionResult.quota),
    (500, ConnectionResult.failed),
    (302, ConnectionResult.failed),
    (200, ConnectionResult.failed),
  ]) {
    test('HTTP $status is classified without exposing the response body', () async {
      final client = MockClient((_) async => http.Response('secret echo', status));
      addTearDown(client.close);
      expect(
        await ProviderConnection.check(provider: ApiProvider.openai, apiKey: 'key', client: client),
        expected,
      );
    });
  }

  test('timeout includes a stalled response body', () async {
    final body = StreamController<List<int>>();
    final client = MockClient.streaming((_, _) async => http.StreamedResponse(body.stream, 200));
    addTearDown(client.close);
    expect(
      await ProviderConnection.check(
        provider: ApiProvider.openai,
        apiKey: 'key',
        client: client,
        timeout: const Duration(milliseconds: 20),
      ),
      ConnectionResult.offline,
    );
    await body.close();
  });

  testWidgets('double tap, changed key, language switch and disposal are safe', (t) async {
    var calls = 0;
    final responses = <Completer<http.Response>>[];
    http.Client createClient() => MockClient((_) {
      calls++;
      final pending = Completer<http.Response>();
      responses.add(pending);
      return pending.future;
    });
    Future<void> mount(String key, {String lang = 'en'}) => t.pumpWidget(
      MaterialApp(
        locale: Locale(lang),
        supportedLocales: const [Locale('en'), Locale('th')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: ConnectionTest(
            provider: ApiProvider.openai,
            apiKey: key,
            mode: MindMode.work,
            createClient: createClient,
          ),
        ),
      ),
    );
    await mount('first');
    await t.tap(find.text('Test connection'));
    await t.tap(find.text('Test connection'));
    await t.pump();
    expect(calls, 1);
    await mount('second');
    responses[0].complete(http.Response('{"data":[]}', 200));
    await t.pump();
    expect(find.byKey(const ValueKey('connection-result')), findsNothing);
    await t.tap(find.text('Test connection'));
    await t.pump();
    await mount('second', lang: 'th');
    await t.pumpAndSettle();
    responses[1].complete(http.Response('{"data":[]}', 200));
    await t.pumpAndSettle();
    expect(
      find.text(const S(AppLang.th).connectionResult(ConnectionResult.connected)),
      findsOneWidget,
    );
    await t.tap(find.text(const S(AppLang.th).connectionTest));
    await t.pump();
    await t.pumpWidget(const SizedBox.shrink());
    responses[2].complete(http.Response('denied', 401));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
