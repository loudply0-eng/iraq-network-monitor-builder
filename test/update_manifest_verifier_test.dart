import 'dart:convert';

import 'package:abrj_iraq/services/update_manifest_verifier.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SimpleKeyPair keyPair;
  late String publicKeyBase64;

  setUp(() async {
    keyPair = await Ed25519().newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    publicKeyBase64 = base64Encode(publicKey.bytes);
  });

  test('accepts a correctly signed manifest before parsing it', () async {
    final payload = utf8.encode(
      '{"latest_version":"1.0.23+26","platform":"android"}',
    );
    final signature = await Ed25519().sign(payload, keyPair: keyPair);

    final decoded = await UpdateManifestVerifier.verify(
      manifestBytes: payload,
      signatureBase64: base64Encode(signature.bytes),
      publicKeyBase64: publicKeyBase64,
    );

    expect(decoded['latest_version'], '1.0.23+26');
    expect(decoded['platform'], 'android');
  });

  test('rejects a manifest whose bytes were modified after signing', () async {
    final payload = utf8.encode('{"latest_version":"1.0.23+26"}');
    final signature = await Ed25519().sign(payload, keyPair: keyPair);
    final modified = utf8.encode('{"latest_version":"9.9.99+99"}');

    expect(
      () => UpdateManifestVerifier.verify(
        manifestBytes: modified,
        signatureBase64: base64Encode(signature.bytes),
        publicKeyBase64: publicKeyBase64,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects malformed public keys and signatures', () async {
    final payload = utf8.encode('{"latest_version":"1.0.23+26"}');

    expect(
      () => UpdateManifestVerifier.verify(
        manifestBytes: payload,
        signatureBase64: base64Encode(<int>[1, 2, 3]),
        publicKeyBase64: publicKeyBase64,
      ),
      throwsA(isA<FormatException>()),
    );

    expect(
      () => UpdateManifestVerifier.verify(
        manifestBytes: payload,
        signatureBase64: base64Encode(List<int>.filled(64, 0)),
        publicKeyBase64: base64Encode(<int>[1, 2, 3]),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
