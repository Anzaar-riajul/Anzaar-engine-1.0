// Copyright (c) Techuboard Authors.
// Apache License 2.0 / MIT.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:techuboard_android/ime/techu_avro_parser.dart';
import 'package:techuboard_android/ui/app_components.dart';

/// TechuAvro Keyboard settings and live testing playground.
class TechuAvroPage extends StatefulWidget {
  const TechuAvroPage({super.key});

  @override
  State<TechuAvroPage> createState() => _TechuAvroPageState();
}

class _TechuAvroPageState extends State<TechuAvroPage> {
  final _parser = TechuAvroParser();
  final _inputController = TextEditingController();
  String _convertedBangla = '';

  static const _channel = MethodChannel('com.techuboard.app/permissions');

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final text = _inputController.text;
    setState(() {
      _convertedBangla = _parser.parse(text);
    });
  }

  Future<void> _openKeyboardSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openKeyboardSettings');
    } catch (_) {
      // Fallback
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TechuAvro Keyboard'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Banner Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1B2A38), const Color(0xFF131D27)]
                    : [const Color(0xFFE3F2FD), const Color(0xFFBBDEFB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF2C3E50) : const Color(0xFF90CAF9),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.keyboard_rounded, color: Colors.blue, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TechuAvro Phonetic Keyboard',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Avro phonetic typing with 1-tap clipboard paste bar',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Text(
                  '• Phonetic Bengali: Type "ami banglay gan gai" -> get "আমি বাংলায় গান গাই"\n'
                  '• Top Clipboard Bar: 1-tap pasting from Techuboard in WhatsApp, Notes, etc.\n'
                  '• Clean English Interface: Modern design without cluttered scripts.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Android Activation Section
          if (Platform.isAndroid) ...[
            TechuSection(
              title: 'Keyboard Setup',
              children: [
                ListTile(
                  leading: const TechuIcon(Icons.settings_suggest_rounded),
                  title: const Text('Enable TechuAvro in Android Settings'),
                  subtitle: const Text('Allow TechuAvro as an available input method'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openKeyboardSettings,
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Interactive Testing Playground
          TechuSection(
            title: 'TechuAvro Live Testing Playground',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _inputController,
                      decoration: InputDecoration(
                        labelText: 'Type in English (e.g. ami, kemon acho, bangla)',
                        hintText: 'ami banglay gan gai...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        suffixIcon: _inputController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () => _inputController.clear(),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Live Bengali Output (TechuAvro):',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1C222B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? const Color(0xFF2E3846) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        _convertedBangla.isEmpty
                            ? 'The converted Bengali will appear here live...'
                            : _convertedBangla,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: _convertedBangla.isEmpty
                              ? theme.disabledColor
                              : (isDark ? Colors.cyanAccent : Colors.blue.shade900),
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Quick sample chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildSampleChip('ami bangla valobashi'),
                        _buildSampleChip('tumi kemon acho'),
                        _buildSampleChip('shonar bangla'),
                        _buildSampleChip('techuboard'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSampleChip(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 12)),
      onPressed: () {
        _inputController.text = text;
      },
    );
  }
}
