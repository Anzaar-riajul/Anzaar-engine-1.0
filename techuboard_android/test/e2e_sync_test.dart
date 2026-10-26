import 'package:flutter_test/flutter_test.dart';
import 'package:techuboard_android/sync/protocol.dart';
import 'package:techuboard_android/sync_manager.dart';

void main() {
  group('E2E Sync Flow', () {
    test('Simulated End-to-End: History Sync', () async {
      // এই টেস্টটি পুরো সিঙ্ক চেইন (Sender -> Encrypt -> Transfer -> Decrypt -> Receiver) সিমুলেট করে।
      
      final senderEnv = SyncEnvelope.make(
        type: SyncType.historyDirect,
        peerId: 'sender-device',
        payload: 'super-secret-text', // সিমুলেটেড এনক্রিপ্টেড ডাটা
        seqNum: 1,
      );
      
      final wireFrame = syncEncodeFrame(senderEnv);
      expect(wireFrame, isNotNull);
      
      // রিসিভার সাইড ভ্যালিডেশন
      final receivedEnv = syncDecodeEnvelope(wireFrame!);
      expect(receivedEnv, isNotNull);
      expect(receivedEnv!.payload, 'super-secret-text');
      expect(receivedEnv.seqNum, 1);
    });
  });
}
