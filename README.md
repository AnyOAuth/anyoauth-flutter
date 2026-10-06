# anyoauth_client

Generated local-only AnyOAuth flutter client, version 0.1.0. MIT licensed.
Schema SHA-256: 1b99cb23da24b2aa0af33d45aadf907de460185671bc29fa61402450e390d6a2; generator version: 1.
Package coordinates are not a claim of registry publication.

## Backend-mediated sign-in

The current API requires confidential backend redemption. Keep credentials on your backend.
This package has no HTTP operations. It exposes only createTransaction, pkceChallenge,
authorizationUrl and validateCallback, plus schema-derived public models and validateSchema.
Server request models are excluded from generation.

1. Register an exact HTTPS callback owned by your backend (HTTP loopback for development).
2. Create a transaction and securely bind state/verifier/expiry to the initiating app session.
   Transfer the verifier to your backend using your authenticated secure application protocol,
   never a URL. Native storage must use OS-protected storage. Timestamps are Unix seconds.
3. Open the authorization URL in an OS browser authentication session.
4. The backend validates the saved redirect, state and expiry, atomically consumes the
   transaction even on denial, redeems the code once, and issues your own application session.
5. Return control through an application-controlled mechanism. Authenticate that return;
   custom-scheme URLs are not supported as AnyOAuth registered callbacks. The native helper
   can validate an HTTPS callback forwarded by your backend, but cannot replace backend validation.

Never store verifier/tokens in URLs. Helpers do not provide persistence, browser binding,
or atomic consumption. Repeated validation alone does not prevent replay.
Only Google/GitHub and S256 are supported. Origins reject credentials, path, query and fragment;
callbacks reject credentials/query/fragment at registration and match the saved URL exactly.
Duplicate query parameters (including percent-encoded aliases) are rejected on callback.

## Usage

```dart
final client = AnyOAuth(clientId: 'your-public-client-id');
final transaction = client.createTransaction();
final url = client.authorizationUrl(provider: 'google', redirectUri: 'https://your-backend.example/auth/callback', state: transaction.state, codeChallenge: transaction.codeChallenge);
```

Decode models through fromJson to validate required fields, types,
nullability, enum/constant values and schema constraints. Optional response additions are accepted.
Use validateSchema for array/string aliases. Model constructors are value containers;
decoders perform validation. No response model triggers network access.

## Build and conformance (from this package directory)

```sh
dart pub get
dart analyze
dart run test/models.dart
mkdir -p build
dart compile exe test/conformance.dart -o build/conformance
build/conformance < input.json
# Flutter applications may use flutter pub get instead.
```

Pure Dart library usable in Flutter, Dart SDK >=3.3.0 <4.0.0. crypto 3.0.6 is pinned. No Flutter plugin or platform channel is needed. Random.secure fails rather than using insecure entropy on unsupported platforms.

The runner reads one JSON object from stdin and writes one JSON object to stdout.
Build tools may log to stderr; run the built executable for protocol-only output.
Run the cross-language protocol suite with Node 18+: node conformance.test.mjs
followed by the runner command and its arguments (for example,
node conformance.test.mjs build/conformance).
Input: {action, baseUrl?, clientId?, params?}. Actions: createTransaction, pkceChallenge,
authorizationUrl, validateCallback. Confidential HTTP actions return unsupported_action.
Parameters: pkceChallenge {codeVerifier}; authorizationUrl {provider, redirectUri, state,
codeChallenge}; validateCallback {callbackUrl, redirectUri, state, expiresAt}.
Output: {ok:true,result} or {ok:false,error:{status:0,code,message}}. Error messages
do not contain raw input or credentials. The canonical RFC7636 test input is:

```json
{"action":"pkceChallenge","params":{"codeVerifier":"dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"}}
```

Expected result: dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk hashes to
E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM.
Regenerate from the parent repository with node sdks/generate.mjs --target=flutter.

## Source and releases

Repository: https://github.com/AnyOAuth/anyoauth-flutter

GitHub prerelease: https://github.com/AnyOAuth/anyoauth-flutter/releases/tag/v0.1.0

Clone this repository, then run `node verify.mjs` with the native toolchain installed to build and execute the package's conformance suite. Source is generated in the AnyOAuth monorepo; propose changes there so every language stays aligned. GitHub hosts source archives and checksums. Package registry publication is separate.

This initial source release has full advertised-method conformance coverage. Runtime line/branch coverage for the whole language matrix remains a separate release gate; see https://anyoauth.com/docs/libraries/.
