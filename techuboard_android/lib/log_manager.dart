import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'database/app_log_repository.dart';

class LogManager extends ChangeNotifier {
  static final LogManager instance = LogManager._();
  LogManager._();

  Timer? _notifyDebounce;
  String? currentTraceId;

  void startTrace() => currentTraceId = const Uuid().v4();
  void endTrace() => currentTraceId = null;

  Future<List<AppLogRecord>> fetchPage({
    required int offset,
    required int limit,
  }) {
    return AppLogRepository.instance.fetchPage(offset: offset, limit: limit);
  }

  Future<int> count() => AppLogRepository.instance.count();

  void log(String message, {String level = 'info', Map<String, dynamic>? metadata}) {
    final logData = {
      'ts': DateTime.now().toIso8601String(),
      'level': level.toUpperCase(),
      'message': message,
      if (currentTraceId != null) 'traceId': currentTraceId,
      if (metadata != null) 'metadata': metadata,
    };
    
    final jsonMessage = jsonEncode(logData);
    
    if (kDebugMode) {
      debugPrint(jsonMessage);
    }
    unawaited(AppLogRepository.instance.insert(level: level, message: jsonMessage));
    _scheduleNotify();
  }

  void _scheduleNotify() {
    _notifyDebounce?.cancel();
    _notifyDebounce = Timer(const Duration(milliseconds: 100), () {
      notifyListeners();
    });
  }

  Future<void> clear() async {
    await AppLogRepository.instance.clearAll();
    notifyListeners();
  }
}

void appLog(String message, {String level = 'info', Map<String, dynamic>? metadata}) {
  LogManager.instance.log(message, level: level, metadata: metadata);
}
