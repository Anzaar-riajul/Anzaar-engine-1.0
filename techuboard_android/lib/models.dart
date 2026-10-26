import 'dart:io';

class HistoryItem {
  final String type; // 'text', 'image', 'rtf', 'pdf', 'fileURL', 'fileURLs'
  final dynamic value;

  HistoryItem({required this.type, required this.value});

  Map<String, dynamic> toJson() {
    // Match Swift enum Codable structure
    // Swift case text(String) encodes as {"text": "..."}
    return {type: value};
  }

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    final type = json.keys.first;
    return HistoryItem(type: type, value: json[type]);
  }

  String get title {
    switch (type) {
      case 'text':
        // Bound both string processing and paragraph shaping for list cards.
        // Copy, search and the full preview continue to use the original value.
        final text = value as String;
        var end = text.length > 600 ? 600 : text.length;
        if (end < text.length &&
            end > 0 &&
            text.codeUnitAt(end - 1) >= 0xD800 &&
            text.codeUnitAt(end - 1) <= 0xDBFF) {
          end--;
        }
        final preview = text.substring(0, end).trim().replaceAll('\n', ' ');
        return end < text.length ? '$preview…' : preview;
      case 'image':
        return '[Image]';
      case 'fileURL':
        return '[File] ${value.toString().split(Platform.pathSeparator).last}';
      case 'fileURLs':
        final paths = value as List<String>;
        return '[${paths.length} Files] ${paths.first.split(Platform.pathSeparator).last}';
      default:
        return '[$type]';
    }
  }
}

class HistoryEntry {
  final HistoryItem item;
  final DateTime date;
  final String? sourceApp;
  final String? contentHash;

  HistoryEntry({
    required this.item,
    required this.date,
    this.sourceApp,
    this.contentHash,
  });

  Map<String, dynamic> toJson() {
    return {
      'item': item.toJson(),
      'date': date
          .toUtc()
          .toIso8601String(), // Ensure UTC with 'Z' for Swift compatibility
      'sourceApp': sourceApp,
      'contentHash': contentHash,
    };
  }

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    // Handle different Date formats if necessary. Swift default is often seconds since 2001.
    // But let's assume standard ISO for simplicity or handle Swift's double format.
    DateTime date;
    if (json['date'] is String) {
      date = DateTime.parse(json['date']);
    } else if (json['date'] is num) {
      // Swift Reference Date (Jan 1, 2001)
      date = DateTime.fromMillisecondsSinceEpoch(
        (json['date'] * 1000 + 978307200000).toInt(),
      );
    } else {
      date = DateTime.now();
    }

    return HistoryEntry(
      item: HistoryItem.fromJson(json['item']),
      date: date,
      sourceApp: json['sourceApp'],
      contentHash: json['contentHash'],
    );
  }
}

class NotificationEntry {
  final String id;
  final String? notificationKey;
  final String packageName;
  final String appName;
  final String title;
  final String? subtitle;
  final String body;
  final int postTime;
  final String? groupKey;
  final bool isClearable;

  /// WeChat (and similar) in-place updates: previous snapshot kept with this flag
  /// so history retains every message while the live slot stays unique.
  final bool isArchived;

  /// 同步状态：0 = 待同步（默认），1 = Mac 已 ack 确认送达。
  /// 仅在本地维护，不随 toJson 序列化到 wire（Mac 侧按 id 去重，不需要此字段）。
  final int syncState;
  final Map<String, dynamic> extras;

  NotificationEntry({
    required this.id,
    this.notificationKey,
    required this.packageName,
    required this.appName,
    required this.title,
    this.subtitle,
    required this.body,
    required this.postTime,
    this.groupKey,
    this.isClearable = true,
    this.isArchived = false,
    this.syncState = 0,
    this.extras = const {},
  });

  NotificationEntry copyWith({
    String? id,
    String? notificationKey,
    String? packageName,
    String? appName,
    String? title,
    String? subtitle,
    String? body,
    int? postTime,
    String? groupKey,
    bool? isClearable,
    bool? isArchived,
    int? syncState,
    Map<String, dynamic>? extras,
  }) {
    return NotificationEntry(
      id: id ?? this.id,
      notificationKey: notificationKey ?? this.notificationKey,
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      body: body ?? this.body,
      postTime: postTime ?? this.postTime,
      groupKey: groupKey ?? this.groupKey,
      isClearable: isClearable ?? this.isClearable,
      isArchived: isArchived ?? this.isArchived,
      syncState: syncState ?? this.syncState,
      extras: extras ?? this.extras,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'notificationKey': notificationKey,
    'packageName': packageName,
    'appName': appName,
    'title': title,
    'subtitle': subtitle,
    'body': body,
    'postTime': postTime,
    'groupKey': groupKey,
    'isClearable': isClearable,
    'isArchived': isArchived,
    'extras': extras,
  };

  factory NotificationEntry.fromJson(Map<String, dynamic> json) {
    final extras = Map<String, dynamic>.from(json['extras'] as Map? ?? {});
    final archivedFlag =
        json['isArchived'] == true ||
        extras['techuArchived'] == true ||
        extras['techuArchived']?.toString() == 'true';
    return NotificationEntry(
      id: json['id'],
      notificationKey: json['notificationKey'],
      packageName: json['packageName'],
      appName: json['appName'],
      title: json['title'],
      subtitle: json['subtitle'],
      body: json['body'] ?? '',
      postTime:
          (json['postTime'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      groupKey: json['groupKey'],
      isClearable: json['isClearable'] ?? true,
      isArchived: archivedFlag,
      extras: extras,
    );
  }
}

class NotificationDismissRequest {
  final String packageName;
  final String? groupKey;
  final String? notificationKey;

  NotificationDismissRequest({
    required this.packageName,
    this.groupKey,
    this.notificationKey,
  });

  Map<String, dynamic> toJson() => {
    'packageName': packageName,
    'groupKey': groupKey,
    'notificationKey': notificationKey,
  };

  factory NotificationDismissRequest.fromJson(Map<String, dynamic> json) {
    return NotificationDismissRequest(
      packageName: json['packageName'],
      groupKey: json['groupKey'],
      notificationKey: json['notificationKey'],
    );
  }
}

class NotificationListenerStatus {
  final bool permissionGranted;
  final bool serviceConnected;
  final int activeNotificationCount;

  const NotificationListenerStatus({
    required this.permissionGranted,
    required this.serviceConnected,
    required this.activeNotificationCount,
  });

  factory NotificationListenerStatus.fromMap(Map<dynamic, dynamic> map) {
    return NotificationListenerStatus(
      permissionGranted: map['permissionGranted'] as bool? ?? false,
      serviceConnected: map['serviceConnected'] as bool? ?? false,
      activeNotificationCount:
          (map['activeNotificationCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class SnippetItem {
  final String id;
  final String folderId;
  final String title;
  final String content;
  final int updatedAt;
  final int sortOrder;
  final String? deviceName;

  const SnippetItem({
    required this.id,
    required this.folderId,
    required this.title,
    required this.content,
    required this.updatedAt,
    this.sortOrder = 0,
    this.deviceName,
  });

  SnippetItem copyWith({
    String? id,
    String? folderId,
    String? title,
    String? content,
    int? updatedAt,
    int? sortOrder,
    String? deviceName,
  }) {
    return SnippetItem(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      title: title ?? this.title,
      content: content ?? this.content,
      updatedAt: updatedAt ?? this.updatedAt,
      sortOrder: sortOrder ?? this.sortOrder,
      deviceName: deviceName ?? this.deviceName,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'folderId': folderId,
    'title': title,
    'content': content,
    'updatedAt': updatedAt,
    'sortOrder': sortOrder,
    if (deviceName != null) 'deviceName': deviceName,
  };

  factory SnippetItem.fromJson(
    Map<String, dynamic> json, {
    String? defaultFolderId,
  }) {
    return SnippetItem(
      id: json['id'] as String? ?? json['id']?.toString() ?? '',
      folderId: json['folderId'] as String? ?? defaultFolderId ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      updatedAt:
          (json['updatedAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      deviceName: json['deviceName'] as String?,
    );
  }
}

class SnippetFolderItem {
  final String id;
  final String title;
  final bool isEnabled;
  final int updatedAt;
  final int sortOrder;
  final List<SnippetItem> snippets;
  final String? deviceName;

  const SnippetFolderItem({
    required this.id,
    required this.title,
    this.isEnabled = true,
    required this.updatedAt,
    this.sortOrder = 0,
    this.snippets = const [],
    this.deviceName,
  });

  SnippetFolderItem copyWith({
    String? id,
    String? title,
    bool? isEnabled,
    int? updatedAt,
    int? sortOrder,
    List<SnippetItem>? snippets,
    String? deviceName,
  }) {
    return SnippetFolderItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isEnabled: isEnabled ?? this.isEnabled,
      updatedAt: updatedAt ?? this.updatedAt,
      sortOrder: sortOrder ?? this.sortOrder,
      snippets: snippets ?? this.snippets,
      deviceName: deviceName ?? this.deviceName,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isEnabled': isEnabled,
    'updatedAt': updatedAt,
    'sortOrder': sortOrder,
    'snippets': snippets.map((s) => s.toJson()).toList(),
    if (deviceName != null) 'deviceName': deviceName,
  };

  factory SnippetFolderItem.fromJson(Map<String, dynamic> json) {
    final folderId = json['id'] as String? ?? json['id']?.toString() ?? '';
    final rawSnippets = json['snippets'] as List<dynamic>? ?? [];
    return SnippetFolderItem(
      id: folderId,
      title: json['title'] as String? ?? '',
      isEnabled: json['isEnabled'] as bool? ?? (json['isEnabled'] == 1),
      updatedAt:
          (json['updatedAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      deviceName: json['deviceName'] as String?,
      snippets: rawSnippets
          .map(
            (s) => SnippetItem.fromJson(
              s as Map<String, dynamic>,
              defaultFolderId: folderId,
            ),
          )
          .toList(),
    );
  }
}
