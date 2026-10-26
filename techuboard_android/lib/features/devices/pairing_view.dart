import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../sync_manager.dart';
import '../../sync/pairing_manager.dart';
import '../../sync/peer_identity.dart';

class PairingView extends StatefulWidget {
  const PairingView({Key? key}) : super(key: key);

  @override
  State<PairingView> createState() => _PairingViewState();
}

class _PairingViewState extends State<PairingView> {
  bool _showScanner = false;
  Map<String, dynamic>? _myPayload;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadQrPayload();
  }

  Future<void> _loadQrPayload() async {
    try {
      final identity = await PeerIdentity.loadOrCreate();
      final addresses = await SyncManager.instance.localIPv4Addresses();
      final host = addresses.isNotEmpty ? addresses.first : '127.0.0.1';
      final payload = await PairingManager.instance.generatePairingPayload(
        peerId: SyncManager.instance.peerId,
        displayName: SyncManager.instance.displayName,
        host: host,
        port: SyncManager.instance.port,
        identity: identity,
      );
      if (mounted) {
        setState(() {
          _myPayload = payload;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onDetect(BarcodeCapture capture) async {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final data = PairingManager.instance.parsePairingQr(raw);
      if (data != null) {
        // Stop scanner and connect
        setState(() => _showScanner = false);
        await PairingManager.instance.trustPeer(
          peerId: data['id'],
          displayName: data['name'],
          publicKeyHex: data['pk'],
        );
        await SyncManager.instance.connectManualPeer(data['ip'], data['port']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Successfully linked with ${data['name']}!')),
          );
        }
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Link Device (WhatsApp Style)'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _showScanner
              ? Stack(
                  children: [
                    MobileScanner(onDetect: _onDetect),
                    Positioned(
                      top: 20,
                      left: 20,
                      child: FloatingActionButton(
                        mini: true,
                        backgroundColor: Colors.black54,
                        child: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => setState(() => _showScanner = false),
                      ),
                    ),
                  ],
                )
              : Padding(
                  const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Link a Companion Device',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Scan this QR code with your other Techuboard app to instantly sync history & files securely.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 32),
                      if (_myPayload != null)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 10)
                            ],
                          ),
                          child: QrImageView(
                            data: jsonEncode(_myPayload),
                            version: QrVersions.auto,
                            size: 220.0,
                          ),
                        ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan QR Code on Another Device'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: () => setState(() => _showScanner = true),
                      ),
                    ],
                  ),
                ),
    );
  }
}
