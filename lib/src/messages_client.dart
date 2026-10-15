// Copyright 2026 Kevin Moore. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Signature for executing external OS processes (`osascript`, `swift`),
/// injectable in tests to verify client behavior without a live browser.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

Future<ProcessResult> _defaultProcessRunner(
  String executable,
  List<String> arguments,
) => Process.run(executable, arguments);

/// Interface for inspecting and automating the Google Messages PWA.
abstract interface class MessagesClient {
  /// Lists conversations from the sidebar, optionally paginating
  /// [loadMorePages] times via the `"Load more conversations"` control without
  /// selecting any conversation.
  Future<List<ConversationSummary>> listConversations({int loadMorePages = 0});

  /// Reads messages from the currently open conversation without clicking any
  /// conversation row in the sidebar.
  Future<ThreadReadResult> readActiveThread({int scrollUpPages = 0});

  /// Reads messages for the conversation matching [queryOrId].
  ///
  /// Enforces [checkUnreadSafety]: if the matched conversation is unread and
  /// [allowMarkRead] is `false`, returns the sidebar snippet without clicking
  /// the conversation. When switching to an already-read conversation, restores
  /// the previously active conversation afterward.
  Future<ThreadReadResult> readThread(
    String queryOrId, {
    int scrollUpPages = 0,
    int loadMorePages = 0,
    bool allowMarkRead = false,
  });

  /// Lists conversations from the "Spam & blocked" modal dialog and closes the
  /// modal when finished.
  Future<List<SpamConversationSummary>> listSpamAndBlocked({
    int scrollPages = 3,
  });

  /// Sends [text] to the conversation matching [queryOrId] using JXA
  /// `InputEvent` composition paired with a native `AXPress` on `Send SMS`.
  ///
  /// Enforces [checkUnreadSafety] before switching threads unless
  /// [allowMarkRead] is `true`. When [dryRun] is `true`, validates the target
  /// conversation and unread safety without typing or sending.
  Future<SendMessageResult> sendMessage(
    String queryOrId,
    String text, {
    int loadMorePages = 0,
    bool allowMarkRead = false,
    bool dryRun = false,
  });

  /// Archives conversations matching each entry in [queriesOrIds] via the
  /// sidebar options menu (`button.menu-button` -> `Archive`) without opening
  /// or marking unread threads as read.
  Future<List<ArchiveConversationResult>> archiveConversations(
    List<String> queriesOrIds, {
    int loadMorePages = 0,
    bool dryRun = false,
  });

  /// Blocks and optionally reports spam on conversations matching each entry in
  /// [queriesOrIds] via the sidebar options menu (`button.menu-button` ->
  /// `Block & report spam` -> `OK`).
  Future<List<BlockConversationResult>> blockConversations(
    List<String> queriesOrIds, {
    bool reportSpam = true,
    int loadMorePages = 0,
    bool dryRun = false,
  });

  /// Marks the conversation matching [queryOrId] as unread (`unread: true`) or
  /// read (`unread: false`) via the sidebar options menu (`button.menu-button`
  /// -> `Mark as unread` / `Mark as read`).
  Future<ConversationSummary> setConversationUnread(
    String queryOrId, {
    required bool unread,
    int loadMorePages = 0,
    bool dryRun = false,
  });

  /// Audits the live Google Messages DOM (zero clicks) to verify that all
  /// required CSS selectors and `data-e2e-*` contracts are present.
  Future<DomHealthReport> checkDomHealth();
}

/// Exception thrown when the Google Messages PWA cannot be reached or parsed.
final class MessagesClientException implements Exception {
  final String message;

  const MessagesClientException(this.message);

  @override
  String toString() => 'MessagesClientException: $message';
}

/// Hybrid client that prefers [JxaMessagesClient] and falls back to
/// [AxMessagesClient] when JXA JavaScript execution is disabled.
final class HybridMessagesClient implements MessagesClient {
  final MessagesBackend backend;
  final MessagesClient _jxa;
  final MessagesClient _ax;

  HybridMessagesClient({
    this.backend = MessagesBackend.auto,
    MessagesClient? jxaClient,
    MessagesClient? axClient,
  }) : _jxa = jxaClient ?? const JxaMessagesClient(),
       _ax = axClient ?? const AxMessagesClient();

  @override
  Future<List<ConversationSummary>> listConversations({
    int loadMorePages = 0,
  }) => _runWithPolicy(
    (client) => client.listConversations(loadMorePages: loadMorePages),
  );

  @override
  Future<ThreadReadResult> readActiveThread({int scrollUpPages = 0}) =>
      _runWithPolicy(
        (client) => client.readActiveThread(scrollUpPages: scrollUpPages),
      );

  @override
  Future<ThreadReadResult> readThread(
    String queryOrId, {
    int scrollUpPages = 0,
    int loadMorePages = 0,
    bool allowMarkRead = false,
  }) => _runWithPolicy(
    (client) => client.readThread(
      queryOrId,
      scrollUpPages: scrollUpPages,
      loadMorePages: loadMorePages,
      allowMarkRead: allowMarkRead,
    ),
  );

  @override
  Future<List<SpamConversationSummary>> listSpamAndBlocked({
    int scrollPages = 3,
  }) => _runWithPolicy(
    (client) => client.listSpamAndBlocked(scrollPages: scrollPages),
  );

  @override
  Future<SendMessageResult> sendMessage(
    String queryOrId,
    String text, {
    int loadMorePages = 0,
    bool allowMarkRead = false,
    bool dryRun = false,
  }) => _runWithPolicy(
    (client) => client.sendMessage(
      queryOrId,
      text,
      loadMorePages: loadMorePages,
      allowMarkRead: allowMarkRead,
      dryRun: dryRun,
    ),
  );

  @override
  Future<List<ArchiveConversationResult>> archiveConversations(
    List<String> queriesOrIds, {
    int loadMorePages = 0,
    bool dryRun = false,
  }) => _runWithPolicy(
    (client) => client.archiveConversations(
      queriesOrIds,
      loadMorePages: loadMorePages,
      dryRun: dryRun,
    ),
  );

  @override
  Future<List<BlockConversationResult>> blockConversations(
    List<String> queriesOrIds, {
    bool reportSpam = true,
    int loadMorePages = 0,
    bool dryRun = false,
  }) => _runWithPolicy(
    (client) => client.blockConversations(
      queriesOrIds,
      reportSpam: reportSpam,
      loadMorePages: loadMorePages,
      dryRun: dryRun,
    ),
  );

  @override
  Future<ConversationSummary> setConversationUnread(
    String queryOrId, {
    required bool unread,
    int loadMorePages = 0,
    bool dryRun = false,
  }) => _runWithPolicy(
    (client) => client.setConversationUnread(
      queryOrId,
      unread: unread,
      loadMorePages: loadMorePages,
      dryRun: dryRun,
    ),
  );

  @override
  Future<DomHealthReport> checkDomHealth() =>
      _runWithPolicy((client) => client.checkDomHealth());

  Future<T> _runWithPolicy<T>(
    Future<T> Function(MessagesClient client) action,
  ) async {
    switch (backend) {
      case MessagesBackend.jxa:
        return action(_jxa);
      case MessagesBackend.ax:
        return action(_ax);
      case MessagesBackend.auto:
        try {
          return await action(_jxa);
        } on MessagesClientException catch (e) {
          if (_isAppleEventsJsDisabled(e.message)) {
            return action(_ax);
          }
          rethrow;
        }
    }
  }
}

bool _isAppleEventsJsDisabled(String message) =>
    message.contains('Executing JavaScript through AppleScript is turned off');

/// JXA (`osascript -l JavaScript`) client that evaluates DOM queries and
/// actions inside the Google Messages tab in the background
/// (`hasFocus: false`).
final class JxaMessagesClient implements MessagesClient {
  final String chromeBundleId;
  final ProcessRunner _processRunner;

  const JxaMessagesClient({
    this.chromeBundleId = 'com.google.Chrome',
    ProcessRunner processRunner = _defaultProcessRunner,
  }) : _processRunner = processRunner;

  @override
  Future<List<ConversationSummary>> listConversations({
    int loadMorePages = 0,
  }) async {
    final raw = await _runJxa(_buildJxaListScript(loadMorePages));
    final list = jsonDecode(raw) as List<Object?>;
    return [
      for (final item in list)
        ConversationSummary.fromJson(item as Map<String, Object?>),
    ];
  }

  @override
  Future<ThreadReadResult> readActiveThread({int scrollUpPages = 0}) async {
    final raw = await _runJxa(_buildJxaActiveThreadScript(scrollUpPages));
    final map = jsonDecode(raw) as Map<String, Object?>;
    return _parseThreadReadJson(map, MessagesBackend.jxa);
  }

  @override
  Future<ThreadReadResult> readThread(
    String queryOrId, {
    int scrollUpPages = 0,
    int loadMorePages = 0,
    bool allowMarkRead = false,
  }) async {
    final conversations = await listConversations(loadMorePages: loadMorePages);
    final target = _requireSingleMatch(conversations, queryOrId);
    final active = _findActiveConversation(conversations);
    final blockReason = checkUnreadSafety(
      target: target,
      activeConversation: active,
      allowMarkRead: allowMarkRead,
    );
    if (blockReason != null) {
      return _buildSnippetOnlyResult(target, blockReason, MessagesBackend.jxa);
    }

    if (target.isActive || (active != null && target.id == active.id)) {
      return readActiveThread(scrollUpPages: scrollUpPages);
    }

    final raw = await _runJxa(
      _buildJxaSwitchAndReadScript(
        targetHref: target.href,
        restoreHref: active?.href,
        scrollUpPages: scrollUpPages,
      ),
    );
    final map = jsonDecode(raw) as Map<String, Object?>;
    return _parseThreadReadJson(
      map,
      MessagesBackend.jxa,
      fallbackConversation: target,
    );
  }

  @override
  Future<List<SpamConversationSummary>> listSpamAndBlocked({
    int scrollPages = 3,
  }) async {
    final raw = await _runJxa(_buildJxaSpamScript(scrollPages));
    final list = jsonDecode(raw) as List<Object?>;
    return [
      for (final item in list)
        SpamConversationSummary.fromJson(item as Map<String, Object?>),
    ];
  }

  @override
  Future<SendMessageResult> sendMessage(
    String queryOrId,
    String text, {
    int loadMorePages = 0,
    bool allowMarkRead = false,
    bool dryRun = false,
  }) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      throw const MessagesClientException('Message text must not be empty.');
    }
    final conversations = await listConversations(loadMorePages: loadMorePages);
    final target = _requireSingleMatch(conversations, queryOrId);
    final active = _findActiveConversation(conversations);
    final blockReason = checkUnreadSafety(
      target: target,
      activeConversation: active,
      allowMarkRead: allowMarkRead,
    );
    if (blockReason != null) {
      throw MessagesClientException(blockReason);
    }
    if (dryRun) {
      return SendMessageResult(
        conversation: target,
        text: trimmedText,
        dryRun: true,
        sent: false,
        backendUsed: MessagesBackend.jxa,
      );
    }
    return _executeSendAndRestore(
      target: target,
      active: active,
      text: trimmedText,
      allowMarkRead: allowMarkRead,
    );
  }

  Future<SendMessageResult> _executeSendAndRestore({
    required ConversationSummary target,
    required ConversationSummary? active,
    required String text,
    required bool allowMarkRead,
  }) async {
    final restoreHref =
        (active != null && !active.isUnread && active.href != target.href)
        ? active.href
        : null;
    String? restored;
    try {
      final prepStatus = await _runJxa(
        _buildJxaSendPrepareScript(
          targetHref: target.href,
          text: text,
          allowMarkRead: allowMarkRead,
        ),
      );
      if (prepStatus != 'READY_TO_PRESS') {
        throw MessagesClientException(
          'Failed to prepare message in "${target.name}" ($prepStatus).',
        );
      }
      final axStatus = await _runSwift(_buildSwiftPressSendScript());
      if (!axStatus.startsWith('PRESSED:')) {
        throw MessagesClientException(
          'Failed to press Send SMS button via Accessibility ($axStatus).',
        );
      }
    } finally {
      if (restoreHref != null && restoreHref.isNotEmpty) {
        restored = await _runJxa(_buildJxaRestoreThreadScript(restoreHref));
      }
    }
    return SendMessageResult(
      conversation: target,
      text: text,
      dryRun: false,
      sent: true,
      restoredActiveHref: restored,
      backendUsed: MessagesBackend.jxa,
    );
  }

  @override
  Future<List<ArchiveConversationResult>> archiveConversations(
    List<String> queriesOrIds, {
    int loadMorePages = 0,
    bool dryRun = false,
  }) async {
    if (queriesOrIds.isEmpty) return const [];
    final conversations = await listConversations(loadMorePages: loadMorePages);
    final targets = [
      for (final q in queriesOrIds) _requireSingleMatch(conversations, q),
    ];
    if (dryRun) {
      return [
        for (final t in targets)
          ArchiveConversationResult(
            conversation: t,
            dryRun: true,
            archived: false,
            backendUsed: MessagesBackend.jxa,
          ),
      ];
    }
    final raw = await _runJxa(
      _buildJxaArchiveScript([for (final t in targets) t.href]),
    );
    final statuses = jsonDecode(raw) as Map<String, Object?>;
    return [
      for (final t in targets)
        ArchiveConversationResult(
          conversation: t,
          dryRun: false,
          archived: statuses[t.href] == 'ARCHIVED',
          backendUsed: MessagesBackend.jxa,
        ),
    ];
  }

  @override
  Future<List<BlockConversationResult>> blockConversations(
    List<String> queriesOrIds, {
    bool reportSpam = true,
    int loadMorePages = 0,
    bool dryRun = false,
  }) async {
    if (queriesOrIds.isEmpty) return const [];
    final conversations = await listConversations(loadMorePages: loadMorePages);
    final targets = [
      for (final q in queriesOrIds) _requireSingleMatch(conversations, q),
    ];
    if (dryRun) {
      return [
        for (final t in targets)
          BlockConversationResult(
            conversation: t,
            dryRun: true,
            blocked: false,
            reportedSpam: reportSpam,
            backendUsed: MessagesBackend.jxa,
          ),
      ];
    }
    final raw = await _runJxa(
      _buildJxaBlockScript([
        for (final t in targets) t.href,
      ], reportSpam: reportSpam),
    );
    final statuses = jsonDecode(raw) as Map<String, Object?>;
    return [
      for (final t in targets)
        BlockConversationResult(
          conversation: t,
          dryRun: false,
          blocked: statuses[t.href] == 'BLOCKED',
          reportedSpam: reportSpam,
          backendUsed: MessagesBackend.jxa,
        ),
    ];
  }

  @override
  Future<ConversationSummary> setConversationUnread(
    String queryOrId, {
    required bool unread,
    int loadMorePages = 0,
    bool dryRun = false,
  }) async {
    final conversations = await listConversations(loadMorePages: loadMorePages);
    final target = _requireSingleMatch(conversations, queryOrId);
    if (dryRun || target.isUnread == unread) {
      return target;
    }
    final status = await _runJxa(
      _buildJxaSetUnreadScript(targetHref: target.href, unread: unread),
    );
    if (status != 'UPDATED') {
      throw MessagesClientException(
        'Failed to mark "${target.name}" as '
        '${unread ? "unread" : "read"} ($status).',
      );
    }
    return ConversationSummary(
      id: target.id,
      href: target.href,
      name: target.name,
      snippet: target.snippet,
      timestamp: target.timestamp,
      timestampLabel: target.timestampLabel,
      isUnread: unread,
      isPinned: target.isPinned,
      isMuted: target.isMuted,
      isActive: target.isActive,
    );
  }

  @override
  Future<DomHealthReport> checkDomHealth() async {
    final raw = await _runJxa(_buildJxaDomHealthScript());
    final map = jsonDecode(raw) as Map<String, Object?>;
    return DomHealthReport.fromJson(map);
  }

  Future<String> _runJxa(String innerScript) async {
    final wrapped = _wrapJxaTabScript(chromeBundleId, innerScript);
    final result = await _processRunner('osascript', [
      '-l',
      'JavaScript',
      '-e',
      wrapped,
    ]);
    if (result.exitCode != 0) {
      throw MessagesClientException(
        'JXA execution failed: ${(result.stderr as String).trim()}',
      );
    }
    return (result.stdout as String).trim();
  }

  Future<String> _runSwift(String swiftSource) async {
    final result = await _processRunner('swift', ['-e', swiftSource]);
    if (result.exitCode != 0) {
      throw MessagesClientException(
        'Swift AX execution failed: ${(result.stderr as String).trim()}',
      );
    }
    return (result.stdout as String).trim();
  }
}

/// Native macOS Accessibility (`AXUIElement` via Swift) client that reads the
/// Google Messages PWA without requiring `Allow JavaScript from Apple Events`.
final class AxMessagesClient implements MessagesClient {
  final ProcessRunner _processRunner;

  const AxMessagesClient({ProcessRunner processRunner = _defaultProcessRunner})
    : _processRunner = processRunner;

  @override
  Future<List<ConversationSummary>> listConversations({
    int loadMorePages = 0,
  }) async {
    final raw = await _runSwift(_buildSwiftAxScript('list', loadMorePages));
    final map = jsonDecode(raw) as Map<String, Object?>;
    final list = map['conversations'] as List<Object?>? ?? const [];
    return [
      for (final item in list)
        ConversationSummary.fromJson(item as Map<String, Object?>),
    ];
  }

  @override
  Future<ThreadReadResult> readActiveThread({int scrollUpPages = 0}) async {
    final raw = await _runSwift(_buildSwiftAxScript('active', scrollUpPages));
    final map = jsonDecode(raw) as Map<String, Object?>;
    return _parseThreadReadJson(map, MessagesBackend.ax);
  }

  @override
  Future<ThreadReadResult> readThread(
    String queryOrId, {
    int scrollUpPages = 0,
    int loadMorePages = 0,
    bool allowMarkRead = false,
  }) async {
    final conversations = await listConversations(loadMorePages: loadMorePages);
    final target = _requireSingleMatch(conversations, queryOrId);
    final active = _findActiveConversation(conversations);
    final blockReason = checkUnreadSafety(
      target: target,
      activeConversation: active,
      allowMarkRead: allowMarkRead,
    );
    if (blockReason != null) {
      return _buildSnippetOnlyResult(target, blockReason, MessagesBackend.ax);
    }
    if (target.isActive) {
      return readActiveThread(scrollUpPages: scrollUpPages);
    }
    return _buildSnippetOnlyResult(
      target,
      'AX backend operates in strictly zero-click mode for non-active threads; '
      'enable "Allow JavaScript from Apple Events" for background thread '
      'switching.',
      MessagesBackend.ax,
    );
  }

  @override
  Future<List<SpamConversationSummary>> listSpamAndBlocked({
    int scrollPages = 3,
  }) async {
    throw const MessagesClientException(
      'Inspecting the "Spam & blocked" modal requires the JXA backend '
      '("Allow JavaScript from Apple Events").',
    );
  }

  @override
  Future<SendMessageResult> sendMessage(
    String queryOrId,
    String text, {
    int loadMorePages = 0,
    bool allowMarkRead = false,
    bool dryRun = false,
  }) async {
    throw const MessagesClientException(
      'Sending messages requires the hybrid JXA + AX backend '
      '("Allow JavaScript from Apple Events").',
    );
  }

  @override
  Future<List<ArchiveConversationResult>> archiveConversations(
    List<String> queriesOrIds, {
    int loadMorePages = 0,
    bool dryRun = false,
  }) async {
    throw const MessagesClientException(
      'Archiving conversations requires the JXA backend '
      '("Allow JavaScript from Apple Events").',
    );
  }

  @override
  Future<List<BlockConversationResult>> blockConversations(
    List<String> queriesOrIds, {
    bool reportSpam = true,
    int loadMorePages = 0,
    bool dryRun = false,
  }) async {
    throw const MessagesClientException(
      'Blocking conversations requires the JXA backend '
      '("Allow JavaScript from Apple Events").',
    );
  }

  @override
  Future<ConversationSummary> setConversationUnread(
    String queryOrId, {
    required bool unread,
    int loadMorePages = 0,
    bool dryRun = false,
  }) async {
    throw const MessagesClientException(
      'Changing conversation read/unread state requires the JXA backend '
      '("Allow JavaScript from Apple Events").',
    );
  }

  @override
  Future<DomHealthReport> checkDomHealth() async {
    final conversations = await listConversations();
    final counts = <String, int>{'ax.conversations': conversations.length};
    final missing = <String>[if (conversations.isEmpty) 'ax.conversations'];
    return DomHealthReport(
      ok: missing.isEmpty,
      selectorCounts: counts,
      missingRequiredSelectors: missing,
      backendUsed: MessagesBackend.ax,
    );
  }

  Future<String> _runSwift(String swiftSource) async {
    final result = await _processRunner('swift', ['-e', swiftSource]);
    if (result.exitCode != 0) {
      throw MessagesClientException(
        'Swift AX execution failed: ${(result.stderr as String).trim()}',
      );
    }
    return (result.stdout as String).trim();
  }
}

ConversationSummary _requireSingleMatch(
  List<ConversationSummary> conversations,
  String queryOrId,
) {
  final matches = findMatchingConversations(conversations, queryOrId);
  if (matches.isEmpty) {
    throw MessagesClientException(
      'No conversation matching "$queryOrId" in ${conversations.length} '
      'loaded conversations.',
    );
  }
  return matches.first;
}

ConversationSummary? _findActiveConversation(
  Iterable<ConversationSummary> conversations,
) {
  for (final c in conversations) {
    if (c.isActive) return c;
  }
  return null;
}

ThreadReadResult _buildSnippetOnlyResult(
  ConversationSummary target,
  String reason,
  MessagesBackend backend,
) => ThreadReadResult(
  conversation: target,
  messages: [
    if (target.snippet.isNotEmpty)
      ThreadMessage(
        id: 'snippet-${target.id}',
        text: target.snippet,
        ariaLabel: '${target.name}: ${target.snippet}',
        timestamp: target.timestamp,
        isOutgoing: target.snippet.startsWith('You: '),
        isUnread: target.isUnread,
      ),
  ],
  skippedOpenToPreserveUnread: true,
  skippedReason: reason,
  backendUsed: backend,
);

ThreadReadResult _parseThreadReadJson(
  Map<String, Object?> map,
  MessagesBackend backend, {
  ConversationSummary? fallbackConversation,
}) {
  final convJson = map['conversation'] as Map<String, Object?>?;
  final msgsJson = map['messages'] as List<Object?>? ?? const [];
  return ThreadReadResult(
    conversation: convJson != null
        ? ConversationSummary.fromJson(convJson)
        : fallbackConversation,
    messages: [
      for (final m in msgsJson)
        ThreadMessage.fromJson(m as Map<String, Object?>),
    ],
    restoredActiveHref: map['restoredActiveHref'] as String?,
    backendUsed: backend,
  );
}

String _wrapJxaTabScript(String bundleId, String bodyScript) {
  final bundleJson = jsonEncode(bundleId);
  return '''
const chrome = Application($bundleJson);
if (!chrome.running()) {
  throw new Error("Google Chrome is not running.");
}
let msgTab = null;
for (const w of chrome.windows()) {
  for (const t of w.tabs()) {
    const u = t.url() || "";
    if (u.includes("messages.google.com/web")) {
      msgTab = t;
      break;
    }
  }
  if (msgTab) break;
}
if (!msgTab) {
  throw new Error("No open Google Messages (messages.google.com/web) tab or PWA window found.");
}
const domHelpers = ${_domHelpersJsLiteral()};
$bodyScript
''';
}

String _domHelpersJsLiteral() => jsonEncode(r'''
window.__gmessagesHax = {
  listConversations() {
    const items = [...document.querySelectorAll("mws-conversation-list-item")];
    return items.map(item => {
      const a = item.querySelector("a[data-e2e-conversation]");
      const href = a ? (a.getAttribute("href") || "") : "";
      const id = href.split("/").filter(Boolean).pop() || "";
      const name = (item.querySelector("[data-e2e-conversation-name]")?.textContent || "").trim();
      const snippet = (item.querySelector("[data-e2e-conversation-snippet]")?.textContent || "").trim();
      const tsEl = item.querySelector("mws-relative-timestamp div[aria-label], mws-relative-timestamp");
      const timestamp = (tsEl?.textContent || "").trim();
      const timestampLabel = tsEl?.getAttribute("aria-label") || "";
      const isUnread = a?.getAttribute("data-e2e-is-unread") === "true" ||
          item.querySelector(".unread") !== null;
      const isPinned = a?.getAttribute("data-e2e-is-pinned") === "true";
      const isMuted = a?.getAttribute("data-e2e-is-muted") === "true";
      const isActive = Boolean(
        a && (a.classList.contains("selected") || a.getAttribute("aria-selected") === "true")
      );
      return {id, href, name, snippet, timestamp, timestampLabel, isUnread, isPinned, isMuted, isActive};
    });
  },
  readMessages() {
    const wrappers = [...document.querySelectorAll("mws-message-wrapper")];
    return wrappers.map(w => {
      const id = w.getAttribute("msg-id") ||
          w.querySelector("[data-e2e-message-id]")?.getAttribute("data-e2e-message-id") || "";
      const isOutgoing = w.getAttribute("is-outgoing") === "true";
      const isUnread = w.getAttribute("is-unread") === "true";
      const isRcs = w.querySelector("[data-e2e-message-rcs]")?.getAttribute("data-e2e-message-rcs") === "true";
      const focusEl = w.querySelector(".msg-focus-element");
      const ariaLabel = focusEl?.getAttribute("aria-label") || "";
      const textEl = w.querySelector("mws-text-message-part, .text-msg");
      const text = (textEl?.textContent || "").trim() || ariaLabel;
      const tsEl = w.querySelector("mws-relative-timestamp, .msg-timestamp");
      const timestamp = (tsEl?.textContent || "").trim();
      return {id, text, ariaLabel, timestamp, isOutgoing, isUnread, isRcs};
    }).filter(m => m.text.length > 0 || m.ariaLabel.length > 0);
  },
  listSpam() {
    const rows = [...document.querySelectorAll("[data-e2e-spam-and-blocked-conversation]")];
    const urlRegex = /(?:https?:\/\/)?(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(?:\/[^\s"<>)]*)?/g;
    return rows.map(r => {
      const name = (r.querySelector("[data-e2e-spam-and-blocked-conversation-name]")?.textContent || "").trim();
      const snippet = (r.querySelector(".conv-snippet")?.textContent || "").trim();
      const timestamp = (r.querySelector(".conv-timestamp")?.textContent || "").trim();
      const actionLabel = (r.querySelector("[data-e2e-unblock-unspam-button]")?.textContent || "").trim();
      const urls = (snippet.match(urlRegex) || []).filter(u => !/^[0-9.]+$/.test(u));
      return {name, snippet, timestamp, actionLabel, urls};
    });
  },
  checkDomHealth() {
    const required = [
      "mws-conversation-list-item",
      "a[data-e2e-conversation]",
      "[data-e2e-conversation-name]",
      "[data-e2e-conversation-snippet]",
      "mws-conversation-list-item button.menu-button",
      "button[data-e2e-branded-header-menu-button]"
    ];
    const optionalActiveThread = [
      "mws-message-wrapper",
      "div[contenteditable='true'][data-e2e-message-input-box]",
      "mw-message-send-button button"
    ];
    const selectorCounts = {};
    const missingRequiredSelectors = [];
    for (const sel of required) {
      const count = document.querySelectorAll(sel).length;
      selectorCounts[sel] = count;
      if (count === 0) missingRequiredSelectors.push(sel);
    }
    for (const sel of optionalActiveThread) {
      selectorCounts[sel] = document.querySelectorAll(sel).length;
    }
    return {
      ok: missingRequiredSelectors.length === 0,
      selectorCounts,
      missingRequiredSelectors
    };
  }
};
''');

String _buildJxaDomHealthScript() => '''
msgTab.execute({javascript: domHelpers});
msgTab.execute({javascript: "JSON.stringify(window.__gmessagesHax.checkDomHealth())"});
''';

String _buildJxaSendPrepareScript({
  required String targetHref,
  required String text,
  required bool allowMarkRead,
}) {
  final targetHrefJson = jsonEncode(targetHref);
  final textJson = jsonEncode(text);
  final allowUnreadJson = jsonEncode(allowMarkRead);
  return '''
const targetHref = $targetHrefJson;
const messageText = $textJson;
const allowUnread = $allowUnreadJson;
const switched = msgTab.execute({javascript: `(() => {
  const a = document.querySelector('a[href="' + ${jsonEncode(targetHref)} + '"]');
  if (!a) return "NOT_FOUND";
  if (!${jsonEncode(allowMarkRead)} && a.getAttribute("data-e2e-is-unread") === "true") {
    return "UNREAD_ABORT";
  }
  a.click();
  return "OK";
})()`});
if (switched !== "OK") {
  switched;
} else {
  delay(0.8);
  const typed = msgTab.execute({javascript: `(() => {
    const box = document.querySelector('div[contenteditable="true"][data-e2e-message-input-box]');
    if (!box) return "NO_COMPOSE_BOX";
    box.focus();
    box.textContent = $textJson;
    box.dispatchEvent(new InputEvent("input", {bubbles: true, data: $textJson, inputType: "insertText"}));
    return "TYPED";
  })()`});
  if (typed !== "TYPED") {
    typed;
  } else {
    delay(0.45);
    msgTab.execute({javascript: `(() => {
      const btn = document.querySelector("mw-message-send-button button");
      if (!btn) return "NO_SEND_BUTTON";
      if (btn.disabled) return "SEND_BUTTON_DISABLED";
      return "READY_TO_PRESS";
    })()`});
  }
}
''';
}

String _buildJxaRestoreThreadScript(String restoreHref) =>
    '''
msgTab.execute({javascript: `(() => {
  const a = document.querySelector('a[href="' + ${jsonEncode(restoreHref)} + '"]');
  if (a && a.getAttribute("data-e2e-is-unread") !== "true") {
    a.click();
  }
  const first = document.querySelector("mws-conversation-list-item");
  if (first) first.scrollIntoView({block: "start"});
})()`});
delay(0.35);
msgTab.execute({javascript: "location.pathname"});
''';

String _buildJxaArchiveScript(List<String> targetHrefs) {
  final hrefsJson = jsonEncode(targetHrefs);
  return '''
const targets = $hrefsJson;
const outcomes = {};
for (const href of targets) {
  const opened = msgTab.execute({javascript: `(() => {
    const a = document.querySelector("a[href=\\"\${href}\\"]");
    if (!a) return "NOT_FOUND";
    a.scrollIntoView({block: "nearest"});
    const item = a.closest("mws-conversation-list-item");
    const btn = item ? item.querySelector("button.menu-button") : null;
    if (!btn) return "NO_MENU_BTN";
    btn.click();
    return "OPENED";
  })()`});
  if (opened !== "OPENED") {
    outcomes[href] = opened;
    continue;
  }
  delay(0.2);
  const clicked = msgTab.execute({javascript: `(() => {
    const archiveBtn = Array.from(document.querySelectorAll("[role=menuitem], .mat-mdc-menu-item"))
      .find(el => (el.innerText || "").trim() === "Archive");
    if (!archiveBtn) return "NO_ARCHIVE_ITEM";
    archiveBtn.click();
    return "ARCHIVED";
  })()`});
  outcomes[href] = clicked;
  delay(0.35);
}
JSON.stringify(outcomes);
''';
}

String _buildJxaBlockScript(
  List<String> targetHrefs, {
  required bool reportSpam,
}) {
  final hrefsJson = jsonEncode(targetHrefs);
  final wantReportJson = jsonEncode(reportSpam);
  return '''
const targets = $hrefsJson;
const wantReport = $wantReportJson;
const outcomes = {};
for (const href of targets) {
  const opened = msgTab.execute({javascript: `(() => {
    const a = document.querySelector("a[href=\\"\${href}\\"]");
    if (!a) return "NOT_FOUND";
    a.scrollIntoView({block: "nearest"});
    const item = a.closest("mws-conversation-list-item");
    const btn = item ? item.querySelector("button.menu-button") : null;
    if (!btn) return "NO_MENU_BTN";
    btn.click();
    return "OPENED";
  })()`});
  if (opened !== "OPENED") {
    outcomes[href] = opened;
    continue;
  }
  delay(0.25);
  const dialogOpened = msgTab.execute({javascript: `(() => {
    const blockBtn = Array.from(document.querySelectorAll("[role=menuitem], .mat-mdc-menu-item"))
      .find(el => (el.innerText || "").includes("Block"));
    if (!blockBtn) return "NO_BLOCK_ITEM";
    blockBtn.click();
    return "DIALOG_OPENED";
  })()`});
  if (dialogOpened !== "DIALOG_OPENED") {
    outcomes[href] = dialogOpened;
    continue;
  }
  delay(0.35);
  const confirmed = msgTab.execute({javascript: `(() => {
    const dlg = document.querySelector("mat-dialog-container, [role=dialog]");
    if (!dlg) return "NO_DIALOG";
    const cb = dlg.querySelector("input[type=checkbox]");
    if (cb && Boolean(cb.checked) !== $wantReportJson) {
      cb.click();
    }
    const okBtn = dlg.querySelector("button[aria-label=OK], button.primary-button");
    if (!okBtn) return "NO_OK_BTN";
    okBtn.click();
    return "BLOCKED";
  })()`});
  outcomes[href] = confirmed;
  delay(0.5);
}
JSON.stringify(outcomes);
''';
}

String _buildJxaSetUnreadScript({
  required String targetHref,
  required bool unread,
}) {
  final targetLabel = unread ? 'Mark as unread' : 'Mark as read';
  return '''
const opened = msgTab.execute({javascript: `(() => {
  const a = document.querySelector('a[href="' + ${jsonEncode(targetHref)} + '"]');
  if (!a) return "NOT_FOUND";
  a.scrollIntoView({block: "nearest"});
  const item = a.closest("mws-conversation-list-item");
  const btn = item ? item.querySelector("button.menu-button") : null;
  if (!btn) return "NO_MENU_BTN";
  btn.click();
  return "OPENED";
})()`});
if (opened !== "OPENED") {
  opened;
} else {
  delay(0.2);
  msgTab.execute({javascript: `(() => {
    const itemBtn = Array.from(document.querySelectorAll("[role=menuitem], .mat-mdc-menu-item"))
      .find(el => (el.innerText || "").trim() === ${jsonEncode(targetLabel)});
    if (!itemBtn) return "NO_MENU_ITEM";
    itemBtn.click();
    return "UPDATED";
  })()`});
}
''';
}

String _buildSwiftPressSendScript() => r'''
import ApplicationServices
import AppKit
import Foundation

let pwaApps = NSWorkspace.shared.runningApplications.filter {
  ($0.bundleIdentifier ?? "").hasPrefix("com.google.Chrome.app.") ||
  ($0.bundleURL?.path ?? "").contains("Messages.app") ||
  ($0.localizedName ?? "").contains("Messages")
}
let chromeApps = NSWorkspace.shared.runningApplications.filter {
  $0.bundleIdentifier == "com.google.Chrome"
}

for app in (pwaApps + chromeApps) {
  let axApp = AXUIElementCreateApplication(app.processIdentifier)
  AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
  AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
}
Thread.sleep(forTimeInterval: 0.15)

func attr(_ el: AXUIElement, _ name: String) -> Any? {
  var v: CFTypeRef?
  return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}

func findSendButton(_ el: AXUIElement, _ depth: Int = 0) -> AXUIElement? {
  if depth > 25 { return nil }
  let role = attr(el, kAXRoleAttribute) as? String ?? ""
  if role == "AXButton" {
    let title = attr(el, kAXTitleAttribute) as? String ?? ""
    let desc = attr(el, kAXDescriptionAttribute) as? String ?? ""
    let classes = (attr(el, "AXDOMClassList") as? [String]) ?? []
    if title.contains("Send") || desc.contains("Send") || classes.contains("send-button") {
      return el
    }
  }
  if let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
    for k in kids {
      if let found = findSendButton(k, depth + 1) { return found }
    }
  }
  return nil
}

var sendButton: AXUIElement? = nil
for app in (pwaApps + chromeApps) {
  let axApp = AXUIElementCreateApplication(app.processIdentifier)
  if let wins = attr(axApp, kAXWindowsAttribute) as? [AXUIElement] {
    for w in wins {
      if let found = findSendButton(w) {
        sendButton = found
        break
      }
    }
  }
  if sendButton != nil { break }
}

guard let btn = sendButton else {
  print("SEND_BUTTON_NOT_FOUND")
  exit(0)
}
let err = AXUIElementPerformAction(btn, kAXPressAction as CFString)
print(err == .success ? "PRESSED:0" : "AX_ERROR:\(err.rawValue)")
''';

String _buildJxaSpamScript(int scrollPages) =>
    '''
msgTab.execute({javascript: domHelpers});
let items = [];
try {
  msgTab.execute({javascript: `(() => {
    if (!document.querySelector("mw-spam-and-blocked-conversations")) {
      if (!document.querySelector("mw-nav-drawer nav")) {
        document.querySelector("button[data-e2e-branded-header-menu-button]")?.click();
      }
    }
  })()`});
  delay(0.4);
  msgTab.execute({javascript: `(() => {
    if (!document.querySelector("mw-spam-and-blocked-conversations")) {
      document.querySelector("button[data-e2e-nav-item=SPAM]")?.click();
    }
  })()`});
  for (let w = 0; w < 12; w++) {
    delay(0.4);
    const ready = Number(msgTab.execute({javascript: "String(document.querySelectorAll(\\"[data-e2e-spam-and-blocked-conversation]\\").length)"}));
    if (ready > 0) break;
  }
  for (let i = 0; i < $scrollPages; i++) {
    const prev = Number(msgTab.execute({javascript: "String(document.querySelectorAll(\\"[data-e2e-spam-and-blocked-conversation]\\").length)"}));
    msgTab.execute({javascript: `(() => {
      const rows = document.querySelectorAll("[data-e2e-spam-and-blocked-conversation]");
      if (rows.length) rows[rows.length - 1].scrollIntoView({block: "end"});
    })()`});
    delay(0.8);
    const next = Number(msgTab.execute({javascript: "String(document.querySelectorAll(\\"[data-e2e-spam-and-blocked-conversation]\\").length)"}));
    if (next === prev && next > 0) break;
  }
  items = JSON.parse(msgTab.execute({javascript: "JSON.stringify(window.__gmessagesHax.listSpam())"}));
} finally {
  msgTab.execute({javascript: `document.querySelector("mat-dialog-actions button[aria-label=Done]")?.click();`});
}
JSON.stringify(items);
''';

String _buildJxaListScript(int loadMorePages) =>
    '''
msgTab.execute({javascript: domHelpers});
for (let i = 0; i < $loadMorePages; i++) {
  const clicked = msgTab.execute({javascript: `(() => {
    const btn = document.querySelector("button.load-more, [data-e2e-load-more-conversations]");
    if (!btn) return "none";
    btn.scrollIntoView({block: "end"});
    btn.click();
    return "clicked";
  })()`});
  if (clicked !== "clicked") break;
  delay(1.0);
}
if ($loadMorePages > 0) {
  msgTab.execute({javascript: `document.querySelector("mws-conversation-list-item")?.scrollIntoView({block: "start"});`});
}
msgTab.execute({javascript: "JSON.stringify(window.__gmessagesHax.listConversations())"});
''';

String _buildJxaActiveThreadScript(int scrollUpPages) =>
    '''
msgTab.execute({javascript: domHelpers});
for (let i = 0; i < $scrollUpPages; i++) {
  msgTab.execute({javascript: `(() => {
    const s = document.querySelector("mws-messages-list mws-bottom-anchored");
    if (s) { s.scrollTop = 0; s.dispatchEvent(new Event("scroll")); }
  })()`});
  delay(1.0);
}
msgTab.execute({javascript: `(() => {
  const convs = window.__gmessagesHax.listConversations();
  const active = convs.find(c => c.isActive) || null;
  const messages = window.__gmessagesHax.readMessages();
  return JSON.stringify({conversation: active, messages});
})()`});
''';

String _buildJxaSwitchAndReadScript({
  required String targetHref,
  required String? restoreHref,
  required int scrollUpPages,
}) {
  final targetHrefJson = jsonEncode(targetHref);
  final restoreHrefJson = jsonEncode(restoreHref);
  return '''
msgTab.execute({javascript: domHelpers});
const targetHref = $targetHrefJson;
const restoreHref = $restoreHrefJson;
let messages = [];
let restoredActiveHref = null;
try {
  const switched = msgTab.execute({javascript: `(() => {
    const a = document.querySelector('a[href="' + ${jsonEncode(targetHref)} + '"]');
    if (!a) return "not_found";
    if (a.getAttribute("data-e2e-is-unread") === "true") return "unread_abort";
    a.click();
    return "ok";
  })()`});
  if (switched !== "ok") {
    throw new Error("Refused or failed to switch to thread (" + switched + ").");
  }
  delay(0.8);
  for (let i = 0; i < $scrollUpPages; i++) {
    msgTab.execute({javascript: `(() => {
      const s = document.querySelector("mws-messages-list mws-bottom-anchored");
      if (s) { s.scrollTop = 0; s.dispatchEvent(new Event("scroll")); }
    })()`});
    delay(1.0);
  }
  messages = JSON.parse(msgTab.execute({javascript: "JSON.stringify(window.__gmessagesHax.readMessages())"}));
} finally {
  if (restoreHref) {
    msgTab.execute({javascript: `(() => {
      const a = document.querySelector('a[href="' + ${jsonEncode(restoreHref ?? '')} + '"]');
      if (a && a.getAttribute("data-e2e-is-unread") !== "true") {
        a.click();
      }
      const first = document.querySelector("mws-conversation-list-item");
      if (first) first.scrollIntoView({block: "start"});
    })()`});
    delay(0.4);
    restoredActiveHref = msgTab.execute({javascript: "location.pathname"});
  }
}
JSON.stringify({messages, restoredActiveHref});
''';
}

String _buildSwiftAxScript(String mode, int pages) =>
    '''
import ApplicationServices
import AppKit
import Foundation

let mode = ${jsonEncode(mode)}
let pages = $pages

let pwaApps = NSWorkspace.shared.runningApplications.filter {
  (\$0.bundleIdentifier ?? "").hasPrefix("com.google.Chrome.app.") ||
  (\$0.bundleURL?.path ?? "").contains("Messages.app") ||
  (\$0.localizedName ?? "").contains("Messages")
}
let chromeApps = NSWorkspace.shared.runningApplications.filter {
  \$0.bundleIdentifier == "com.google.Chrome"
}

for app in (pwaApps + chromeApps) {
  let axApp = AXUIElementCreateApplication(app.processIdentifier)
  AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
  AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
}
Thread.sleep(forTimeInterval: 0.25)

func attr(_ el: AXUIElement, _ name: String) -> Any? {
  var v: CFTypeRef?
  return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}

func findWebArea(_ el: AXUIElement, _ depth: Int = 0) -> AXUIElement? {
  if depth > 14 { return nil }
  let role = attr(el, kAXRoleAttribute) as? String ?? ""
  if role == "AXWebArea" {
    let url = (attr(el, kAXURLAttribute) as? URL)?.absoluteString ?? (attr(el, kAXURLAttribute) as? String ?? "")
    let title = attr(el, kAXTitleAttribute) as? String ?? ""
    if url.contains("messages.google.com") || title.contains("Messages") {
      return el
    }
  }
  if let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
    for k in kids {
      if let f = findWebArea(k, depth + 1) { return f }
    }
  }
  return nil
}

var webArea: AXUIElement? = nil
for app in (pwaApps + chromeApps) {
  let axApp = AXUIElementCreateApplication(app.processIdentifier)
  if let wins = attr(axApp, kAXWindowsAttribute) as? [AXUIElement] {
    for w in wins {
      if let found = findWebArea(w) {
        webArea = found
        break
      }
    }
  }
  if webArea != nil { break }
}

guard let root = webArea else {
  fputs("No Google Messages AXWebArea found.\\n", stderr)
  exit(1)
}

func findByClass(_ el: AXUIElement, _ cls: String, _ depth: Int = 0) -> AXUIElement? {
  if depth > 18 { return nil }
  if let classes = attr(el, "AXDOMClassList") as? [String], classes.contains(cls) {
    return el
  }
  if let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
    for k in kids {
      if let f = findByClass(k, cls, depth + 1) { return f }
    }
  }
  return nil
}

func findAllByClass(_ el: AXUIElement, _ cls: String, _ depth: Int = 0, _ out: inout [AXUIElement]) {
  if depth > 20 { return }
  if let classes = attr(el, "AXDOMClassList") as? [String], classes.contains(cls) {
    out.append(el)
  }
  if let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
    for k in kids {
      findAllByClass(k, cls, depth + 1, &out)
    }
  }
}

guard let convListNav = findByClass(root, "conversation-list"),
      let convContainer = findByClass(convListNav, "conv-container") else {
  fputs("Could not locate conversation-list in AXWebArea.\\n", stderr)
  exit(1)
}

if mode == "list" && pages > 0 {
  for _ in 0..<pages {
    if let loadMore = findByClass(convListNav, "load-more") {
      _ = AXUIElementPerformAction(loadMore, "AXScrollToVisible" as CFString)
      _ = AXUIElementPerformAction(loadMore, kAXPressAction as CFString)
      Thread.sleep(forTimeInterval: 1.2)
    }
  }
  if let first = (attr(convContainer, kAXChildrenAttribute) as? [AXUIElement])?.first {
    _ = AXUIElementPerformAction(first, "AXScrollToVisible" as CFString)
  }
}

func collectStaticText(_ el: AXUIElement, _ depth: Int = 0) -> String {
  if depth > 6 { return "" }
  let role = attr(el, kAXRoleAttribute) as? String ?? ""
  if role == "AXStaticText" {
    return attr(el, kAXValueAttribute) as? String ?? ""
  }
  var parts: [String] = []
  if let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
    for k in kids {
      let s = collectStaticText(k, depth + 1)
      if !s.isEmpty { parts.append(s) }
    }
  }
  return parts.joined()
}

let items = (attr(convContainer, kAXChildrenAttribute) as? [AXUIElement]) ?? []
var conversations: [[String: Any]] = []
for (idx, item) in items.enumerated() {
  let classes = (attr(item, "AXDOMClassList") as? [String]) ?? []
  let isActive = classes.contains("selected")
  let isUnread = findByClass(item, "unread") != nil
  let name = findByClass(item, "name").flatMap { attr(\$0, kAXTitleAttribute) as? String } ?? ""
  let snippet = findByClass(item, "snippet-text").map { collectStaticText(\$0) } ?? ""
  let timestamp = findByClass(item, "snippet-timestamp").map { collectStaticText(\$0) } ?? ""
  conversations.append([
    "id": "ax-\\(idx + 1)",
    "href": "",
    "name": name,
    "snippet": snippet,
    "timestamp": timestamp,
    "isUnread": isUnread,
    "isPinned": false,
    "isMuted": false,
    "isActive": isActive
  ])
}

var messages: [[String: Any]] = []
if mode == "active" {
  var msgEls: [AXUIElement] = []
  findAllByClass(root, "msg-focus-element", 0, &msgEls)
  for (idx, m) in msgEls.enumerated() {
    let title = attr(m, kAXTitleAttribute) as? String ?? ""
    if title.isEmpty { continue }
    messages.append([
      "id": "ax-msg-\\(idx + 1)",
      "text": title,
      "ariaLabel": title,
      "timestamp": "",
      "isOutgoing": title.hasPrefix("You said:"),
      "isUnread": false,
      "isRcs": title.contains("End-to-end encrypted")
    ])
  }
}

let activeConv = conversations.first { (\$0["isActive"] as? Bool) == true }
let out: [String: Any] = [
  "conversations": conversations,
  "conversation": activeConv as Any,
  "messages": messages
]
let data = try! JSONSerialization.data(withJSONObject: out, options: [])
print(String(data: data, encoding: .utf8)!)
''';
