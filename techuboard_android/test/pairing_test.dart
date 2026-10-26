import 'package:flutter_test/flutter_test.dart';
import 'package:techuboard_android/sync/pairing_manager.dart';

void main() {
  group('PairingManager Tests', () {
    test('QR Code Payload Parsing', () {
      final validJson = '{"v":1,"id":"test-id","name":"test-name","ip":"192.168.1.1","port":5566,"pk":"abc","psk":"123"}';
      final data = PairingManager.instance.parsePairingQr(validJson);
      
      expect(data, isNotNull);
      expect(data!['id'], 'test-id');
      expect(data['pk'], 'abc');
    });

    test('Invalid QR Payload Rejection', () {
      final invalidJson = '{"v":2,"id":"test-id"}'; // Wrong version
      final data = PairingManager.instance.parsePairingQr(invalidJson);
      expect(data, isNull);
    });
  });
}
