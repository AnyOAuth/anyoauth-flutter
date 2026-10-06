import 'package:anyoauth_client/anyoauth_client.dart';

void main() {
  void check(bool condition) { if (!condition) throw StateError('Model assertion failed'); }
  void rejects(void Function() block) { try { block(); } on SDKError { return; } throw StateError('Expected schema rejection'); }
  final value = <String, dynamic>{'subject': 'google:123', 'provider': 'google', 'providerSubject': '123', 'name': null, 'username': null, 'email': null, 'emailVerified': false, 'avatarUrl': null, 'additive': true};
  final profile = Profile.fromJson(value);
  check(profile.name == null && profile.provider == Provider.google && profile.toJson().containsKey('name'));
  value.remove('name'); rejects(() => Profile.fromJson(value));
  value['name'] = null; value['provider'] = 'other'; rejects(() => Profile.fromJson(value));
  value['provider'] = 'google'; value['emailVerified'] = 1; rejects(() => Profile.fromJson(value));
  check(!ApiError.fromJson({'error': 'denied'}).toJson().containsKey('message'));
  rejects(() => ApiError.fromJson({'error': 'denied', 'message': null}));
  rejects(() => validateSchema('TokenResponse', {'access_token': 'invalid', 'token_type': 'Bearer', 'expires_in': 900, 'scope': 'profile'}));
  print('Passed model decoding checks');
}
