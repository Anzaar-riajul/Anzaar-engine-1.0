import 'package:flutter_test/flutter_test.dart';
import 'package:techuboard_android/sync/protocol.dart';

void main() {
  group('Protocol Tests', () {
    test('Envelope Sequence Number Validation', () {
      final env = SyncEnvelope.make(
        type: SyncType.historyDirect,
        peerId: 'peer1',
        seqNum: 1,
      );
      
      expect(env.seqNum, 1);
      final json = env.toJson();
      expect(json['seqNum'], 1);
    });
  });
}
