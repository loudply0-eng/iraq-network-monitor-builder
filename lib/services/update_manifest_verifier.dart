import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Verifies a detached Ed25519 signature over the exact manifest bytes.
/// Signature verification happens before JSON decoding or trusting metadata.
class UpdateManifestVerifier {
  const UpdateManifestVerifier._();

  static const int maxManifestBytes = 64 * 1024;

  static Future<Map<String, dynamic>> verify({
    required List<int> manifestBytes,
    required String signatureBase64,
    required String publicKeyBase64,
  }) async {
    if (manifestBytes.isEmpty || manifestBytes.length > maxManifestBytes) {
      throw const FormatException('Update manifest has an invalid size.');
    }

    late final List<int> publicKeyBytes;
    late final List<int> signatureBytes;
    try {
      publicKeyBytes = base64Decode(publicKeyBase64.trim());
      signatureBytes = base64Decode(signatureBase64.trim());
    } on FormatException {
      throw const FormatException('Update signature encoding is invalid.');
    }

    if (publicKeyBytes.length != 32 || signatureBytes.length != 64) {
      throw const FormatException('Update signature or public key has an invalid length.');
    }

    final publicKey = SimplePublicKey(
      publicKeyBytes,
      type: KeyPairType.ed25519,
    );
    final signature = Signature(signatureBytes, publicKey: publicKey);
    final isValid = await Ed25519().verify(
      manifestBytes,
      signature: signature,
    );
    if (!isValid) {
      throw const FormatException('Update manifest signature is invalid.');
    }

    final decoded = jsonDecode(utf8.decode(manifestBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Update manifest must be a JSON object.');
    }
    return decoded;
  }
}
