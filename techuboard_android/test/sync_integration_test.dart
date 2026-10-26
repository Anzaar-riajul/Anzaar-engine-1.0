import 'package:flutter_test/flutter_test.dart';
import 'package:techuboard_android/sync/protocol.dart';
import 'package:techuboard_android/sync_manager.dart';

void main() {
  group('Sync Integration Tests', () {
    test('Full Sync Flow: History Direct + ACK', () async {
      // Mocking the SyncManager/SyncEnvelope flow
      final env = SyncEnvelope.make(
        type: SyncType.historyDirect,
        peerId: 'peer1',
        payload: 'encrypted_payload',
        seqNum: 1,
      );
      
      final data = syncEncodeFrame(env);
      expect(data, isNotNull);
      
      final decoded = syncDecodeEnvelope(data!);
      expect(decoded, isNotNull);
      expect(decoded!.type, SyncType.historyDirect);
      expect(decoded.seqNum, 1);
      
      final ack = SyncEnvelope.make(
        type: SyncType.ack,
        peerId: 'peer1',
        hash: 'hash1',
      );
      expect(ack.type, SyncType.ack);
    });
  });
}
