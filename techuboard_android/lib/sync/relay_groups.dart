import 'dart:convert';
import 'package:common_relay/common_relay.dart' as cr;
import 'package:shared_preferences/shared_preferences.dart';
import 'relay_identity.dart';
import 'sodium_helper.dart';

/// Serializes management actions; pending enrollment survives closing the page.
class TechuRelayGroups {
  static Future<void>? _tail;
  static Future<T> run<T>(Future<T> Function() action) {
    final next = (_tail ?? Future<void>.value()).then((_) => action());
    late final Future<void> tail;
    void release() {
      if (identical(_tail, tail)) _tail = null;
    }

    tail = next.then<void>((_) => release(), onError: (Object _) => release());
    _tail = tail;
    return next;
  }

  static String encodeInvitation(Map<String, dynamic> value) =>
      value['short_link'] as String? ??
      'common-relay://join#${base64Url.encode(utf8.encode(jsonEncode(value)))}';
  static Future<Map<String, dynamic>> resolveInvitation(String text) async {
    final raw = text.trim();
    if (raw.startsWith('common-relay://') &&
        !raw.startsWith('common-relay://join#')) {
      final g = await load();
      g.config['app'] = 'techuboard';
      return g.resolveInvitation(raw);
    }
    return decodeInvitation(raw);
  }

  static Map<String, dynamic> decodeInvitation(String text) {
    if (text.length > 8192) throw const FormatException('Invitation too large');
    final raw = text.trim();
    final value = raw.startsWith('common-relay://join#')
        ? utf8.decode(
            base64Url.decode(base64Url.normalize(raw.split('#').last)),
          )
        : raw;
    final code = jsonDecode(value) as Map<String, dynamic>;
    if (code['version'] != 1 ||
        code['app'] != 'techuboard' ||
        code['group'] is! String) {
      throw const FormatException('Invalid Techuboard invitation');
    }
    return code;
  }

  static Future<cr.RelayGroups> load() async {
    final raw = await TechuRelayIdentity.config();
    final c = raw.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    final configured = prefs.getString('syncRelayURL')?.trim() ?? '';
    final saved = (c['url'] as String?)?.trim() ?? '';
    c['url'] = configured.isNotEmpty
        ? configured
        : saved.isNotEmpty
        ? saved
        : 'wss://eglish.top/relay/v1/ws';
    return cr.RelayGroups(await initSodium(), c);
  }

  static Future<void> persist(cr.RelayGroups groups) async {
    final raw = await TechuRelayIdentity.config();
    if (raw.isNotEmpty) {
      final current = jsonDecode(raw) as Map<String, dynamic>;
      if ([
        'device',
        'group',
        'token',
        'secret_key',
      ].any((k) => current[k] != groups.config[k])) {
        throw StateError('Configuration changed during request');
      }
      final old = current['group_entry'] as Map<String, dynamic>?,
          next = groups.config['group_entry'] as Map<String, dynamic>?;
      if (old != null &&
          next != null &&
          (cr.RelayGroups.unpack(old)['revision'] as int) >
              (cr.RelayGroups.unpack(next)['revision'] as int)) {
        return;
      }
    }
    final value = Map<String, dynamic>.from(groups.config)
      ..remove('enrollment_invitation')
      ..remove('enrollment_name')
      ..remove('creation_draft');
    await TechuRelayIdentity.saveConfig(jsonEncode(value));
  }

  static Future<cr.RelayGroups> draft(
    Map<String, dynamic> invitation,
    String device,
  ) async {
    final saved = await pending();
    final marker = saved?.config['enrollment_invitation'] as Map?;
    if (marker != null &&
        marker['group'] == invitation['group'] &&
        marker['url'] == invitation['url'] &&
        ((invitation['id'] != null &&
                marker['id'] == invitation['id'] &&
                marker['secret'] == invitation['secret']) ||
            (invitation['bootstrap'] != null &&
                marker['bootstrap'] == invitation['bootstrap']))) {
      return saved!;
    }
    final existing = await load();
    if (existing.config.containsKey('group_entry')) {
      throw StateError('Already enrolled. Use the existing group.');
    }
    if (existing.config.containsKey('token') &&
        (existing.config['group'] != invitation['group'] ||
            (invitation['url'] != null &&
                invitation['url'] != existing.config['url']))) {
      throw StateError(
        'Existing identity belongs to a different group or server',
      );
    }
    final c = Map<String, dynamic>.from(existing.config);
    final identity = await TechuRelayIdentity.localIdentity();
    c.addAll(identity);
    c['device'] =
        c['device'] ??
        (await SharedPreferences.getInstance()).getString(
          'syncRelayDeviceId',
        ) ??
        device;
    c['app'] = 'techuboard';
    c['group'] = invitation['group'];
    c['url'] = invitation['url'] ?? c['url'];
    c['trusted_peers'] ??= <String, dynamic>{};
    c.putIfAbsent('token', () => cr.hex(existing.sodium.randombytes.buf(32)));
    return cr.RelayGroups(existing.sodium, c);
  }

  static Future<cr.RelayGroups> creationDraft(
    String title,
    String name,
    String device,
  ) async {
    final existing = await load();
    if (existing.config['token'] != null) throw StateError('Already enrolled');
    final saved = await pending();
    if (saved != null) {
      if (saved.config['pending_create'] != null ||
          saved.config['creation_draft'] == true) {
        return saved;
      }
      throw StateError('Finish the pending invitation first');
    }
    final c = <String, dynamic>{
      'url': existing.config['url'],
      'app': 'techuboard',
      'device':
          (await SharedPreferences.getInstance()).getString(
            'syncRelayDeviceId',
          ) ??
          device,
      ...await TechuRelayIdentity.localIdentity(),
    };
    final g = cr.RelayGroups(existing.sodium, c);
    g.prepareCreate(title, name);
    g.config['creation_draft'] = true;
    await savePending(g);
    return g;
  }

  static Future<void> exitGroup({required bool disband}) async {
    final current = await load();
    var raw = await TechuRelayIdentity.groupExit();
    var saved = raw.isEmpty ? null : jsonDecode(raw) as Map<String, dynamic>;
    if (saved != null &&
        [
          'device',
          'group',
          'token',
          'url',
        ].any((key) => saved![key] != current.config[key])) {
      await TechuRelayIdentity.saveGroupExit('');
      raw = '';
      saved = null;
    }
    final g = saved == null ? current : cr.RelayGroups(current.sodium, saved);
    if (raw.isNotEmpty && g.config['exit_disband'] != disband) {
      throw StateError('Retry the pending exit operation');
    }
    await g.prepareExit(disband: disband);
    g.config['exit_disband'] = disband;
    await TechuRelayIdentity.saveGroupExit(jsonEncode(g.config));
    try {
      await g.exit();
    } catch (error) {
      if (error.toString().contains('409')) {
        await TechuRelayIdentity.saveGroupExit(jsonEncode(g.config));
      }
      rethrow;
    }
  }

  static Future<void> clearEnrollment() async {
    final sodium = await initSodium();
    // Change only the relay identity, leaving LAN identity and local data intact.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('syncRelayEnabled', false);
    await prefs.setString(
      'syncRelayDeviceId',
      cr.hex(sodium.randombytes.buf(16)),
    );
    await TechuRelayIdentity.saveConfig('');
    await clearPending();
    await TechuRelayIdentity.saveGroupInvitation('');
    await TechuRelayIdentity.saveGroupExit('');
  }

  static Future<void> savePending(cr.RelayGroups groups) =>
      TechuRelayIdentity.saveGroupDraft(jsonEncode(groups.config));
  static Future<cr.RelayGroups?> pending() async {
    final raw = await TechuRelayIdentity.groupDraft();
    if (raw.isEmpty) return null;
    return cr.RelayGroups(
      await initSodium(),
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  static Future<void> clearPending() => TechuRelayIdentity.saveGroupDraft('');
  static String verificationCode(Map<String, dynamic> request) =>
      cr.RelayGroups.digest(cr.RelayGroups.payload(request))
          .substring(0, 12)
          .toUpperCase()
          .replaceAllMapped(RegExp('.{4}'), (m) => '${m[0]} ')
          .trim();
}
