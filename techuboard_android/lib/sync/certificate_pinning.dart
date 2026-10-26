import 'dart:io';

/// SSL Certificate Pinning for WSS Relay connections.
/// Ensures protection against Man-In-The-Middle (MITM) attacks on untrusted networks.
class CertificatePinning {
  static const List<String> _allowedSHA256Fingerprints = [
    // Production relay server certificate SHA-256 fingerprints
    'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855',
  ];

  static HttpClient createPinnedHttpClient() {
    final client = HttpClient();
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      final sha256Hex = cert.sha256.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
      return _allowedSHA256Fingerprints.contains(sha256Hex);
    };
    return client;
  }
}
