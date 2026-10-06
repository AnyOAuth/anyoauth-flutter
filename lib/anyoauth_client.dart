import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class SDKError implements Exception {
  final int status;
  final String code;
  final String message;
  const SDKError(this.code, this.message, [this.status = 0]);
  @override
  String toString() => '$code: $message';
}
Never _fail(String message) => throw SDKError('invalid_argument', message);
Uri _safeUrl(String text, {bool origin = false, bool query = false}) {
  if (text.isEmpty || RegExp(r'[\s\x00-\x1f\x7f\\]').hasMatch(text) || RegExp(r'%(?![a-fA-F0-9]{2})').hasMatch(text)) _fail('Unsafe URL');
  final Uri u;
  try { u = Uri.parse(text); } catch (_) { _fail('Invalid URL'); }
  if (u.host.isEmpty || u.userInfo.isNotEmpty || text.split('://').last.split('/').first.split('?').first.contains('@') ||
      u.hasFragment || !(u.scheme == 'https' || (u.scheme == 'http' && ['localhost', '127.0.0.1', '::1'].contains(u.host))) ||
      (u.hasPort && (u.port < 1 || u.port > 65535)) || (!query && u.hasQuery) ||
      (origin && u.path != '' && u.path != '/') || text.split('://').last.split('/').first.split('?').first.contains('%')) _fail('Unsafe URL');
  return u;
}
void validateSchema(String name, dynamic value) {
  final s = _nativeSchemas[name];
  if (s == null) _fail('Unknown model');
  _validateValue(s as Map, value);
}
void _validateValue(Map s, dynamic value) {
  if (s.containsKey(r'$ref')) { validateSchema((s[r'$ref'] as String).split('/').last, value); return; }
  final types = s['type'] is List ? s['type'] as List : [s['type']];
  if (value == null) { if (types.contains('null')) return; _fail('Unexpected null'); }
  switch (types.firstWhere((t) => t != 'null')) {
    case 'string':
      if (value is! String) _fail('Expected string');
      final length = value.runes.length;
      if ((s['minLength'] != null && length < s['minLength']) || (s['maxLength'] != null && length > s['maxLength'])) _fail('Invalid string length');
      if (s['pattern'] != null) {
        final pattern = s['pattern'] as String;
        final match = RegExp(pattern).firstMatch(value);
        if (match == null || (pattern.startsWith('^') && pattern.endsWith(r'$') && (match.start != 0 || match.end != value.length))) _fail('Invalid string format');
      }
      if (s['enum'] != null && !(s['enum'] as List).contains(value)) _fail('Invalid enum');
      if (s.containsKey('const') && value != s['const']) _fail('Invalid constant');
      if (s['format'] == 'uri') _safeUrl(value);
    case 'integer':
      if (value is! num || !value.isFinite || value % 1 != 0 || value.abs() > 9007199254740991) _fail('Expected safe integer');
      if (s.containsKey('const') && value != s['const']) _fail('Invalid constant');
    case 'boolean':
      if (value is! bool) _fail('Expected boolean');
    case 'array':
      if (value is! List) _fail('Expected array');
      for (final v in value) { _validateValue(s['items'] as Map, v); }
    case 'object':
      if (value is! Map) _fail('Expected object');
      final props = s['properties'] as Map;
      for (final key in (s['required'] as List?) ?? []) { if (!value.containsKey(key)) _fail('Missing required field'); }
      if (s['additionalProperties'] == false && value.keys.any((k) => !props.containsKey(k))) _fail('Unexpected field');
      for (final key in props.keys) { if (value.containsKey(key)) _validateValue(props[key] as Map, value[key]); }
    default: _fail('Unsupported schema');
  }
}
class AnyOAuth {
  final String clientId;
  final String baseUrl;
  AnyOAuth({required this.clientId, String baseUrl = 'https://api.anyoauth.com'}) : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl {
    _safeUrl(baseUrl, origin: true);
    _validateValue(_nativeSchemas['AuthorizationParameters']['properties']['client_id'] as Map, clientId);
  }
  String pkceChallenge(String verifier) {
    validateSchema('CodeVerifier', verifier);
    return _base64url(sha256.convert(ascii.encode(verifier)).bytes);
  }
  Transaction createTransaction() {
    final rng = Random.secure();
    String random() => _base64url(List.generate(32, (_) => rng.nextInt(256)));
    final state = random(), verifier = random();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return Transaction.fromJson({'state': state, 'codeVerifier': verifier, 'codeChallenge': pkceChallenge(verifier), 'createdAt': now, 'expiresAt': now + 600});
  }
  String authorizationUrl({required String provider, required String redirectUri, required String state, required String codeChallenge}) {
    final params = {'client_id': clientId, 'provider': provider, 'redirect_uri': redirectUri, 'state': state, 'code_challenge': codeChallenge, 'code_challenge_method': 'S256', 'response_type': 'code'};
    validateSchema('AuthorizationParameters', params);
    return Uri.parse('$baseUrl/authorize').replace(queryParameters: params).toString();
  }
  Map<String, String> validateCallback({required String callbackUrl, required String redirectUri, required String state, required int expiresAt}) {
    validateSchema('RedirectUri', redirectUri);
    final u = _safeUrl(callbackUrl, query: true);
    if (callbackUrl.split('?').first != redirectUri) throw const SDKError('invalid_callback', 'Callback does not match saved redirect');
    if (expiresAt <= DateTime.now().millisecondsSinceEpoch ~/ 1000) throw const SDKError('transaction_expired', 'Transaction expired');
    final params = <String, String>{};
    if (u.hasQuery) {
      // Use the original encoded query: Uri.query may normalize percent escapes.
      for (final pair in callbackUrl.substring(callbackUrl.indexOf('?') + 1).split('&')) {
        final eq = pair.indexOf('=');
        final String key, value;
        try {
          key = Uri.decodeQueryComponent(eq < 0 ? pair : pair.substring(0, eq));
          value = Uri.decodeQueryComponent(eq < 0 ? '' : pair.substring(eq + 1));
        } catch (_) { throw const SDKError('invalid_callback', 'Invalid query encoding'); }
        if (params.containsKey(key)) throw const SDKError('invalid_callback', 'Duplicate query parameter');
        params[key] = value;
      }
    }
    if (state.isEmpty || params['state'] != state) throw const SDKError('state_mismatch', 'Callback state mismatch');
    if (params.containsKey('code') == params.containsKey('error') || (params['code'] ?? params['error'] ?? '').isEmpty) throw const SDKError('invalid_callback', 'Expected exactly one code or error');
    if (params.containsKey('code')) { validateSchema('CallbackCode', params['code']); return {'code': params['code']!, 'state': state}; }
    return {'error': params['error']!, 'state': state};
  }
  String _base64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
}

final Map<String, dynamic> _nativeSchemas = jsonDecode(r'''{"Provider":{"type":"string","enum":["google","github"]},"RedirectUri":{"type":"string","format":"uri","maxLength":2048,"x-validation":"redirect","description":"Exact registered HTTPS URL or HTTP loopback; no credentials, query or fragment."},"TokenResponse":{"type":"object","required":["access_token","token_type","expires_in","scope"],"properties":{"access_token":{"type":"string","pattern":"^aop_[A-Za-z0-9_-]{43}$"},"token_type":{"type":"string","const":"Bearer"},"expires_in":{"type":"integer","const":900},"scope":{"type":"string","const":"profile"}}},"Profile":{"type":"object","required":["subject","provider","providerSubject","name","username","email","emailVerified","avatarUrl"],"properties":{"subject":{"type":"string"},"provider":{"$ref":"#/components/schemas/Provider"},"providerSubject":{"type":"string"},"name":{"type":["string","null"]},"username":{"type":["string","null"]},"email":{"type":["string","null"]},"emailVerified":{"type":"boolean"},"avatarUrl":{"type":["string","null"]}}},"ProviderStatus":{"type":"object","required":["id","configured","enabled","available"],"properties":{"id":{"$ref":"#/components/schemas/Provider"},"configured":{"type":"boolean"},"enabled":{"type":"boolean"},"available":{"type":"boolean"}}},"ProviderStatuses":{"type":"array","items":{"$ref":"#/components/schemas/ProviderStatus"}},"ApiError":{"type":"object","required":["error"],"properties":{"error":{"type":"string"},"message":{"type":"string"}}},"Transaction":{"type":"object","required":["state","codeVerifier","codeChallenge","createdAt","expiresAt"],"properties":{"state":{"type":"string","pattern":"^[A-Za-z0-9_-]{43}$"},"codeVerifier":{"type":"string","pattern":"^[A-Za-z0-9._~-]{43,128}$"},"codeChallenge":{"type":"string","pattern":"^[A-Za-z0-9_-]{43}$"},"createdAt":{"type":"integer"},"expiresAt":{"type":"integer"}}},"AuthorizationParameters":{"type":"object","additionalProperties":false,"required":["client_id","provider","redirect_uri","state","code_challenge","code_challenge_method","response_type"],"properties":{"client_id":{"type":"string","minLength":1},"provider":{"$ref":"#/components/schemas/Provider"},"redirect_uri":{"$ref":"#/components/schemas/RedirectUri"},"state":{"type":"string","minLength":16,"maxLength":512},"code_challenge":{"type":"string","pattern":"^[A-Za-z0-9_-]{43}$"},"code_challenge_method":{"type":"string","const":"S256"},"response_type":{"type":"string","const":"code"}}},"CodeVerifier":{"type":"string","pattern":"^[A-Za-z0-9._~-]{43,128}$"},"CallbackCode":{"type":"string","minLength":1,"maxLength":200}}''') as Map<String, dynamic>;

enum Provider { google, github; String get wire => name; static Provider fromWire(String value) => values.firstWhere((v) => v.name == value, orElse: () => throw SDKError('invalid_argument', 'Invalid Provider')); }

typedef RedirectUri = String;

class TokenResponse {
  final String access_token;
  final String token_type;
  final int expires_in;
  final String scope;
  const TokenResponse({required this.access_token, required this.token_type, required this.expires_in, required this.scope});
  factory TokenResponse.fromJson(dynamic value) {
    validateSchema("TokenResponse", value);
    final m = value as Map;
    return TokenResponse(access_token: m["access_token"] as String, token_type: m["token_type"] as String, expires_in: (m["expires_in"] as num).toInt(), scope: m["scope"] as String);
  }
  Map<String, dynamic> toJson() => {"access_token": access_token, "token_type": token_type, "expires_in": expires_in, "scope": scope};
}

class Profile {
  final String subject;
  final Provider provider;
  final String providerSubject;
  final String? name;
  final String? username;
  final String? email;
  final bool emailVerified;
  final String? avatarUrl;
  const Profile({required this.subject, required this.provider, required this.providerSubject, required this.name, required this.username, required this.email, required this.emailVerified, required this.avatarUrl});
  factory Profile.fromJson(dynamic value) {
    validateSchema("Profile", value);
    final m = value as Map;
    return Profile(subject: m["subject"] as String, provider: Provider.fromWire(m["provider"] as String), providerSubject: m["providerSubject"] as String, name: m["name"] == null ? null : m["name"] as String, username: m["username"] == null ? null : m["username"] as String, email: m["email"] == null ? null : m["email"] as String, emailVerified: m["emailVerified"] as bool, avatarUrl: m["avatarUrl"] == null ? null : m["avatarUrl"] as String);
  }
  Map<String, dynamic> toJson() => {"subject": subject, "provider": provider.wire, "providerSubject": providerSubject, "name": name, "username": username, "email": email, "emailVerified": emailVerified, "avatarUrl": avatarUrl};
}

class ProviderStatus {
  final Provider id;
  final bool configured;
  final bool enabled;
  final bool available;
  const ProviderStatus({required this.id, required this.configured, required this.enabled, required this.available});
  factory ProviderStatus.fromJson(dynamic value) {
    validateSchema("ProviderStatus", value);
    final m = value as Map;
    return ProviderStatus(id: Provider.fromWire(m["id"] as String), configured: m["configured"] as bool, enabled: m["enabled"] as bool, available: m["available"] as bool);
  }
  Map<String, dynamic> toJson() => {"id": id.wire, "configured": configured, "enabled": enabled, "available": available};
}

typedef ProviderStatuses = List<ProviderStatus>;

class ApiError {
  final String error;
  final String? message;
  const ApiError({required this.error, this.message});
  factory ApiError.fromJson(dynamic value) {
    validateSchema("ApiError", value);
    final m = value as Map;
    return ApiError(error: m["error"] as String, message: m["message"] == null ? null : m["message"] as String);
  }
  Map<String, dynamic> toJson() => {"error": error, if (message != null) "message": message};
}

class Transaction {
  final String state;
  final String codeVerifier;
  final String codeChallenge;
  final int createdAt;
  final int expiresAt;
  const Transaction({required this.state, required this.codeVerifier, required this.codeChallenge, required this.createdAt, required this.expiresAt});
  factory Transaction.fromJson(dynamic value) {
    validateSchema("Transaction", value);
    final m = value as Map;
    return Transaction(state: m["state"] as String, codeVerifier: m["codeVerifier"] as String, codeChallenge: m["codeChallenge"] as String, createdAt: (m["createdAt"] as num).toInt(), expiresAt: (m["expiresAt"] as num).toInt());
  }
  Map<String, dynamic> toJson() => {"state": state, "codeVerifier": codeVerifier, "codeChallenge": codeChallenge, "createdAt": createdAt, "expiresAt": expiresAt};
}
