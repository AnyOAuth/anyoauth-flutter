import 'dart:convert';
import 'dart:io';
import 'package:anyoauth_client/anyoauth_client.dart';

Future<void> main() async {
  Map<String, dynamic> output;
  try {
    final input = jsonDecode(await stdin.transform(utf8.decoder).join()) as Map;
    final p = input['params'] as Map? ?? {};
    String string(String key) { final v = p[key]; if (v is! String) throw const SDKError('invalid_argument', 'Missing string parameter'); return v; }
    final client = AnyOAuth(clientId: input['clientId'] as String? ?? 'conformance', baseUrl: input['baseUrl'] as String? ?? 'https://api.anyoauth.com');
    final dynamic result;
    switch (input['action']) {
      case 'pkceChallenge': result = client.pkceChallenge(string('codeVerifier'));
      case 'createTransaction': result = client.createTransaction().toJson();
      case 'authorizationUrl': result = client.authorizationUrl(provider: string('provider'), redirectUri: string('redirectUri'), state: string('state'), codeChallenge: string('codeChallenge'));
      case 'validateCallback':
        final expiry = p['expiresAt'];
        if (expiry is! num || !expiry.isFinite || expiry % 1 != 0 || expiry.abs() > 9007199254740991) throw const SDKError('invalid_argument', 'Expected integer expiry');
        result = client.validateCallback(callbackUrl: string('callbackUrl'), redirectUri: string('redirectUri'), state: string('state'), expiresAt: expiry.toInt());
      default: throw const SDKError('unsupported_action', 'Client SDK supports local helpers only');
    }
    output = {'ok': true, 'result': result};
  } on SDKError catch (e) { output = {'ok': false, 'error': {'status': e.status, 'code': e.code, 'message': e.message}}; }
  catch (_) { output = {'ok': false, 'error': {'status': 0, 'code': 'invalid_argument', 'message': 'Invalid runner input'}}; }
  stdout.writeln(jsonEncode(output));
}
