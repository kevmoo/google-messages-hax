// Copyright 2026 Kevin Moore. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Execution backend used to inspect the Google Messages PWA.
enum MessagesBackend {
  /// Tries JXA (`osascript`) first and falls back to macOS Accessibility (`ax`)
  /// if Chrome's `Allow JavaScript from Apple Events` setting is disabled.
  auto,

  /// Executes read-only DOM queries via JXA (`tab.execute({javascript: ...})`).
  jxa,

  /// Traverses the Chromium `AXWebArea` tree via Swift `ApplicationServices`.
  ax,
}

/// Summary of a conversation row in the Google Messages sidebar.
final class ConversationSummary {
  final String id;
  final String href;
  final String name;
  final String snippet;
  final String timestamp;
  final String timestampLabel;
  final bool isUnread;
  final bool isPinned;
  final bool isMuted;
  final bool isActive;

  const ConversationSummary({
    required this.id,
    required this.href,
    required this.name,
    required this.snippet,
    required this.timestamp,
    this.timestampLabel = '',
    required this.isUnread,
    this.isPinned = false,
    this.isMuted = false,
    required this.isActive,
  });

  factory ConversationSummary.fromJson(Map<String, Object?> json) {
    final href = json['href'] as String? ?? '';
    final rawId = json['id'] as String? ?? '';
    final resolvedId = rawId.isNotEmpty ? rawId : extractConversationId(href);
    return ConversationSummary(
      id: resolvedId,
      href: href,
      name: json['name'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
      timestampLabel: json['timestampLabel'] as String? ?? '',
      isUnread: json['isUnread'] as bool? ?? false,
      isPinned: json['isPinned'] as bool? ?? false,
      isMuted: json['isMuted'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? false,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'href': href,
    'name': name,
    'snippet': snippet,
    'timestamp': timestamp,
    if (timestampLabel.isNotEmpty) 'timestampLabel': timestampLabel,
    'isUnread': isUnread,
    'isPinned': isPinned,
    'isMuted': isMuted,
    'isActive': isActive,
  };
}

/// A single message within a Google Messages conversation thread.
final class ThreadMessage {
  final String id;
  final String text;
  final String ariaLabel;
  final String timestamp;
  final bool isOutgoing;
  final bool isUnread;
  final bool isRcs;

  const ThreadMessage({
    required this.id,
    required this.text,
    required this.ariaLabel,
    this.timestamp = '',
    required this.isOutgoing,
    this.isUnread = false,
    this.isRcs = false,
  });

  factory ThreadMessage.fromJson(Map<String, Object?> json) => ThreadMessage(
    id: json['id'] as String? ?? '',
    text: json['text'] as String? ?? '',
    ariaLabel: json['ariaLabel'] as String? ?? '',
    timestamp: json['timestamp'] as String? ?? '',
    isOutgoing: json['isOutgoing'] as bool? ?? false,
    isUnread: json['isUnread'] as bool? ?? false,
    isRcs: json['isRcs'] as bool? ?? false,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'ariaLabel': ariaLabel,
    if (timestamp.isNotEmpty) 'timestamp': timestamp,
    'isOutgoing': isOutgoing,
    'isUnread': isUnread,
    'isRcs': isRcs,
  };
}

/// Result of reading a conversation thread.
final class ThreadReadResult {
  final ConversationSummary? conversation;
  final List<ThreadMessage> messages;
  final bool skippedOpenToPreserveUnread;
  final String? skippedReason;
  final String? restoredActiveHref;
  final MessagesBackend backendUsed;

  const ThreadReadResult({
    required this.conversation,
    required this.messages,
    this.skippedOpenToPreserveUnread = false,
    this.skippedReason,
    this.restoredActiveHref,
    required this.backendUsed,
  });

  Map<String, Object?> toJson() => {
    'conversation': conversation?.toJson(),
    'messages': [for (final m in messages) m.toJson()],
    'skippedOpenToPreserveUnread': skippedOpenToPreserveUnread,
    if (skippedReason != null) 'skippedReason': skippedReason,
    if (restoredActiveHref != null) 'restoredActiveHref': restoredActiveHref,
    'backendUsed': backendUsed.name,
  };
}

/// Summary of an entry in the Google Messages "Spam & blocked" dialog.
final class SpamConversationSummary {
  final String name;
  final String snippet;
  final String timestamp;
  final String actionLabel;
  final List<String> urls;

  const SpamConversationSummary({
    required this.name,
    required this.snippet,
    required this.timestamp,
    required this.actionLabel,
    this.urls = const [],
  });

  /// True when the row shows `"Unblock"` (user-blocked number) rather than
  /// `"Not spam"` (auto-filtered or spam-only).
  bool get isBlocked => actionLabel.toLowerCase() == 'unblock';

  factory SpamConversationSummary.fromJson(Map<String, Object?> json) {
    final rawUrls = json['urls'] as List<Object?>? ?? const [];
    return SpamConversationSummary(
      name: json['name'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
      actionLabel: json['actionLabel'] as String? ?? '',
      urls: [for (final u in rawUrls) u as String],
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'snippet': snippet,
    'timestamp': timestamp,
    'actionLabel': actionLabel,
    'isBlocked': isBlocked,
    'urls': urls,
  };
}

/// Extracts the conversation ID segment from a `/web/conversations/<id>` path
/// or full URL.
String extractConversationId(String rawHref) {
  final trimmed = rawHref.trim();
  if (trimmed.isEmpty) return '';
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return '';
  return switch (uri.pathSegments) {
    ['web', 'conversations', final id, ...] when id.isNotEmpty => id,
    [final id] when id.isNotEmpty => id,
    _ => '',
  };
}

/// Filters conversations by unread state, optional search query (matching
/// `name`, `snippet`, or `id`), and optional maximum count.
List<ConversationSummary> filterConversations(
  Iterable<ConversationSummary> conversations, {
  bool unreadOnly = false,
  String? query,
  int? limit,
}) {
  final normalizedQuery = query?.trim().toLowerCase() ?? '';
  final results = <ConversationSummary>[];
  for (final conv in conversations) {
    if (unreadOnly && !conv.isUnread) continue;
    if (normalizedQuery.isNotEmpty && !_matchesSearch(conv, normalizedQuery)) {
      continue;
    }
    results.add(conv);
    if (limit != null && limit > 0 && results.length >= limit) break;
  }
  return results;
}

bool _matchesSearch(ConversationSummary conv, String lowerQuery) =>
    conv.name.toLowerCase().contains(lowerQuery) ||
    conv.snippet.toLowerCase().contains(lowerQuery) ||
    conv.id.toLowerCase().contains(lowerQuery);

/// Finds conversations matching [targetQuery] by exact ID/href first, then
/// case-insensitive contact/group name substring.
List<ConversationSummary> findMatchingConversations(
  Iterable<ConversationSummary> conversations,
  String targetQuery,
) {
  final needle = targetQuery.trim();
  if (needle.isEmpty) return const [];

  final exactMatches = [
    for (final c in conversations)
      if (c.id == needle ||
          c.href == needle ||
          c.name.toLowerCase() == needle.toLowerCase())
        c,
  ];
  if (exactMatches.isNotEmpty) return exactMatches;

  final lowerNeedle = needle.toLowerCase();
  return [
    for (final c in conversations)
      if (c.name.toLowerCase().contains(lowerNeedle) ||
          c.id.toLowerCase().contains(lowerNeedle))
        c,
  ];
}

/// Evaluates whether opening [target] in the UI is safe under read-only rules.
///
/// Returns `null` if safe to read full messages, or a human-readable reason
/// string explaining why clicking [target] is blocked to preserve unread state.
String? checkUnreadSafety({
  required ConversationSummary target,
  required ConversationSummary? activeConversation,
  required bool allowMarkRead,
}) {
  if (allowMarkRead || target.isActive) return null;
  if (activeConversation != null &&
      target.id.isNotEmpty &&
      target.id == activeConversation.id) {
    return null;
  }
  if (target.isUnread) {
    return 'Conversation "${target.name}" (${target.id}) is UNREAD. '
        'Skipping thread click to preserve unread state; returning sidebar '
        'snippet only (pass --allow-mark-read to open).';
  }
  if (activeConversation != null && activeConversation.isUnread) {
    return 'Currently active conversation "${activeConversation.name}" is '
        'UNREAD. Refusing to switch threads so restoring the active thread '
        'does not mark it read.';
  }
  return null;
}
