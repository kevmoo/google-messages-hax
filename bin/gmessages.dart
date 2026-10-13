// Copyright 2026 Kevin Moore. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:google_messages_hax/google_messages_hax.dart';

Future<void> main(List<String> arguments) async {
  final parser = _buildArgParser();
  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}\n');
    stderr.writeln(_usageText(parser));
    exitCode = 64;
    return;
  }

  if (results.flag('help')) {
    stdout.writeln(_usageText(parser));
    return;
  }

  try {
    exitCode = await _runCli(results, parser);
  } on MessagesClientException catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    exitCode = 64;
  }
}

ArgParser _buildArgParser() => ArgParser()
  ..addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: 'Print this usage information.',
  )
  ..addOption(
    'backend',
    allowed: ['auto', 'jxa', 'ax'],
    defaultsTo: 'auto',
    help: 'Inspection backend (auto tries JXA then falls back to Swift AX).',
  )
  ..addFlag(
    'unread-only',
    abbr: 'u',
    negatable: false,
    help: 'Filter conversation list to unread threads only.',
  )
  ..addOption(
    'limit',
    abbr: 'n',
    defaultsTo: '25',
    help: 'Maximum number of conversations or messages to display.',
  )
  ..addOption(
    'load-more',
    defaultsTo: '0',
    help: 'Number of sidebar pagination batches to load before listing.',
  )
  ..addOption(
    'scroll-pages',
    defaultsTo: '0',
    help: 'Number of message history pages to scroll up inside a thread.',
  )
  ..addFlag(
    'allow-mark-read',
    negatable: false,
    help:
        'Allow clicking into an UNREAD conversation (marks it as read). '
        'Disabled by default.',
  )
  ..addFlag(
    'dry-run',
    negatable: false,
    help:
        'Validate target conversation and unread safety for send/archive '
        'without mutating the UI.',
  )
  ..addFlag('json', negatable: false, help: 'Emit structured JSON output.');

String _usageText(ArgParser parser) => '''
CLI for the Google Messages Chrome PWA on macOS.

Usage:
  gmessages [list] [options]
  gmessages search <query> [options]
  gmessages active [options]
  gmessages read <name-or-id> [options]
  gmessages spam [options]
  gmessages send <name-or-id> <message> [--dry-run] [--allow-mark-read]
  gmessages archive <name-or-id> [...more] [--dry-run]
  gmessages mark-unread <name-or-id> [--dry-run]
  gmessages mark-read <name-or-id> [--dry-run]
  gmessages doctor [options]

Options:
${parser.usage}''';

Future<int> _runCli(ArgResults results, ArgParser parser) async {
  final backend = _parseBackend(results.option('backend')!);
  final limit = _parseNonNegativeInt(results.option('limit')!, 'limit');
  final loadMore = _parseNonNegativeInt(
    results.option('load-more')!,
    'load-more',
  );
  final scrollPages = _parseNonNegativeInt(
    results.option('scroll-pages')!,
    'scroll-pages',
  );
  final unreadOnly = results.flag('unread-only');
  final allowMarkRead = results.flag('allow-mark-read');
  final dryRun = results.flag('dry-run');
  final asJson = results.flag('json');

  final rest = results.rest;
  final command = rest.isEmpty ? 'list' : rest.first;
  final client = HybridMessagesClient(backend: backend);

  return switch (command) {
    'list' => _handleList(
      client: client,
      unreadOnly: unreadOnly,
      loadMore: loadMore,
      limit: limit,
      asJson: asJson,
    ),
    'search' => _handleSearch(
      rest: rest,
      client: client,
      unreadOnly: unreadOnly,
      loadMore: loadMore,
      limit: limit,
      asJson: asJson,
    ),
    'active' => _handleActive(
      client: client,
      scrollPages: scrollPages,
      limit: limit,
      asJson: asJson,
    ),
    'read' => _handleRead(
      rest: rest,
      client: client,
      scrollPages: scrollPages,
      loadMore: loadMore,
      allowMarkRead: allowMarkRead,
      limit: limit,
      asJson: asJson,
    ),
    'spam' => _handleSpam(
      client: client,
      scrollPages: scrollPages > 0 ? scrollPages : 3,
      limit: limit,
      asJson: asJson,
    ),
    'send' => _handleSend(
      rest: rest,
      client: client,
      loadMore: loadMore,
      allowMarkRead: allowMarkRead,
      dryRun: dryRun,
      asJson: asJson,
    ),
    'archive' => _handleArchive(
      rest: rest,
      client: client,
      loadMore: loadMore,
      dryRun: dryRun,
      asJson: asJson,
    ),
    'mark-unread' || 'mark-read' => _handleSetUnread(
      rest: rest,
      unread: command == 'mark-unread',
      client: client,
      loadMore: loadMore,
      dryRun: dryRun,
      asJson: asJson,
    ),
    'doctor' => _handleDoctor(client: client, asJson: asJson),
    _ => _handleUnknownCommand(command, parser),
  };
}

int _handleUnknownCommand(String command, ArgParser parser) {
  stderr.writeln('Unknown command "$command".\n');
  stderr.writeln(_usageText(parser));
  return 64;
}

Future<int> _handleSearch({
  required List<String> rest,
  required MessagesClient client,
  required bool unreadOnly,
  required int loadMore,
  required int limit,
  required bool asJson,
}) {
  if (rest.length < 2) {
    throw const FormatException('Missing <query> for "search" command.');
  }
  return _handleList(
    client: client,
    unreadOnly: unreadOnly,
    query: rest.skip(1).join(' '),
    loadMore: loadMore,
    limit: limit,
    asJson: asJson,
  );
}

Future<int> _handleActive({
  required MessagesClient client,
  required int scrollPages,
  required int limit,
  required bool asJson,
}) async {
  final thread = await client.readActiveThread(scrollUpPages: scrollPages);
  _printThreadResult(thread, limit: limit, asJson: asJson);
  return 0;
}

Future<int> _handleRead({
  required List<String> rest,
  required MessagesClient client,
  required int scrollPages,
  required int loadMore,
  required bool allowMarkRead,
  required int limit,
  required bool asJson,
}) async {
  if (rest.length < 2) {
    throw const FormatException('Missing <name-or-id> for "read" command.');
  }
  final targetQuery = rest.skip(1).join(' ');
  final thread = await client.readThread(
    targetQuery,
    scrollUpPages: scrollPages,
    loadMorePages: loadMore,
    allowMarkRead: allowMarkRead,
  );
  _printThreadResult(thread, limit: limit, asJson: asJson);
  return 0;
}

Future<int> _handleSend({
  required List<String> rest,
  required MessagesClient client,
  required int loadMore,
  required bool allowMarkRead,
  required bool dryRun,
  required bool asJson,
}) async {
  if (rest.length < 3) {
    throw const FormatException(
      'Usage: gmessages send <name-or-id> <message> [--dry-run]',
    );
  }
  final targetQuery = rest[1];
  final messageText = rest.skip(2).join(' ');
  final result = await client.sendMessage(
    targetQuery,
    messageText,
    loadMorePages: loadMore,
    allowMarkRead: allowMarkRead,
    dryRun: dryRun,
  );
  if (asJson) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
    return 0;
  }
  final prefix = result.dryRun ? '[DRY-RUN] Would send' : 'Sent';
  stdout.writeln(
    '$prefix "${result.text}" to ${result.conversation.name} '
    '[${result.conversation.id}]',
  );
  return 0;
}

Future<int> _handleArchive({
  required List<String> rest,
  required MessagesClient client,
  required int loadMore,
  required bool dryRun,
  required bool asJson,
}) async {
  if (rest.length < 2) {
    throw const FormatException(
      'Usage: gmessages archive <name-or-id> [...more] [--dry-run]',
    );
  }
  final targets = rest.skip(1).toList();
  final results = await client.archiveConversations(
    targets,
    loadMorePages: loadMore,
    dryRun: dryRun,
  );
  if (asJson) {
    stdout.writeln(
      const JsonEncoder.withIndent(
        '  ',
      ).convert([for (final r in results) r.toJson()]),
    );
    return 0;
  }
  for (final r in results) {
    final status = r.dryRun
        ? '[DRY-RUN] Would archive'
        : (r.archived ? 'Archived' : 'Failed to archive');
    stdout.writeln('$status ${r.conversation.name} [${r.conversation.id}]');
  }
  return results.every((r) => r.dryRun || r.archived) ? 0 : 1;
}

Future<int> _handleSetUnread({
  required List<String> rest,
  required bool unread,
  required MessagesClient client,
  required int loadMore,
  required bool dryRun,
  required bool asJson,
}) async {
  final cmdName = unread ? 'mark-unread' : 'mark-read';
  if (rest.length < 2) {
    throw FormatException('Usage: gmessages $cmdName <name-or-id> [--dry-run]');
  }
  final targetQuery = rest.skip(1).join(' ');
  final updated = await client.setConversationUnread(
    targetQuery,
    unread: unread,
    loadMorePages: loadMore,
    dryRun: dryRun,
  );
  if (asJson) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(updated.toJson()),
    );
    return 0;
  }
  final stateLabel = unread ? 'UNREAD' : 'READ';
  final prefix = dryRun ? '[DRY-RUN] Would mark' : 'Marked';
  stdout.writeln('$prefix ${updated.name} [${updated.id}] as $stateLabel');
  return 0;
}

Future<int> _handleDoctor({
  required MessagesClient client,
  required bool asJson,
}) async {
  final report = await client.checkDomHealth();
  if (asJson) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
    return report.ok ? 0 : 1;
  }
  stdout.writeln(
    'DOM Health (${report.backendUsed.name}): ${report.ok ? "OK" : "FAILED"}',
  );
  for (final entry in report.selectorCounts.entries) {
    stdout.writeln('  ${entry.key}: ${entry.value}');
  }
  if (report.missingRequiredSelectors.isNotEmpty) {
    stderr.writeln(
      'Missing required selectors: '
      '${report.missingRequiredSelectors.join(", ")}',
    );
    return 1;
  }
  return 0;
}

Future<int> _handleList({
  required MessagesClient client,
  required bool unreadOnly,
  String? query,
  required int loadMore,
  required int limit,
  required bool asJson,
}) async {
  final all = await client.listConversations(loadMorePages: loadMore);
  final filtered = filterConversations(
    all,
    unreadOnly: unreadOnly,
    query: query,
    limit: limit > 0 ? limit : null,
  );
  if (asJson) {
    stdout.writeln(
      const JsonEncoder.withIndent(
        '  ',
      ).convert([for (final c in filtered) c.toJson()]),
    );
    return 0;
  }

  final unreadTotal = all.where((c) => c.isUnread).length;
  stdout.writeln(
    'Conversations: showing ${filtered.length} of ${all.length} loaded '
    '($unreadTotal unread)',
  );
  for (final c in filtered) {
    final badges = <String>[
      if (c.isUnread) 'UNREAD',
      if (c.isActive) 'ACTIVE',
      if (c.isPinned) 'PINNED',
    ];
    final badgeText = badges.isEmpty ? 'READ' : badges.join(',');
    final ts = c.timestamp.isEmpty ? '-' : c.timestamp;
    stdout.writeln('[${c.id}] [$badgeText] ${c.name} ($ts): ${c.snippet}');
  }
  return 0;
}

Future<int> _handleSpam({
  required MessagesClient client,
  required int scrollPages,
  required int limit,
  required bool asJson,
}) async {
  final all = await client.listSpamAndBlocked(scrollPages: scrollPages);
  final shown = limit > 0 && all.length > limit ? all.sublist(0, limit) : all;
  if (asJson) {
    stdout.writeln(
      const JsonEncoder.withIndent(
        '  ',
      ).convert([for (final s in shown) s.toJson()]),
    );
    return 0;
  }

  final blockedCount = all.where((s) => s.isBlocked).length;
  stdout.writeln(
    'Spam & blocked: showing ${shown.length} of ${all.length} '
    '($blockedCount user-blocked, ${all.length - blockedCount} spam-flagged)',
  );
  for (final s in shown) {
    final kind = s.isBlocked ? 'BLOCKED' : 'SPAM';
    final urlPart = s.urls.isEmpty ? '' : ' | URLs: ${s.urls.join(', ')}';
    stdout.writeln('[$kind] ${s.name} (${s.timestamp}): ${s.snippet}$urlPart');
  }
  return 0;
}

void _printThreadResult(
  ThreadReadResult result, {
  required int limit,
  required bool asJson,
}) {
  final messages = limit > 0 && result.messages.length > limit
      ? result.messages.sublist(result.messages.length - limit)
      : result.messages;

  if (asJson) {
    final cropped = ThreadReadResult(
      conversation: result.conversation,
      messages: messages,
      skippedOpenToPreserveUnread: result.skippedOpenToPreserveUnread,
      skippedReason: result.skippedReason,
      restoredActiveHref: result.restoredActiveHref,
      backendUsed: result.backendUsed,
    );
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(cropped.toJson()),
    );
    return;
  }

  final conv = result.conversation;
  if (conv != null) {
    final status = conv.isUnread ? 'UNREAD' : 'READ';
    stdout.writeln('Thread: ${conv.name} [${conv.id}] ($status)');
  }
  if (result.skippedReason != null) {
    stdout.writeln('Notice: ${result.skippedReason}');
  }
  stdout.writeln(
    'Messages (${messages.length} of ${result.messages.length}, '
    'backend: ${result.backendUsed.name}):',
  );
  for (final m in messages) {
    final dir = m.isOutgoing ? 'OUT' : 'IN';
    final label = m.ariaLabel.isNotEmpty ? m.ariaLabel : m.text;
    stdout.writeln('  [$dir] (${m.id}) $label');
  }
}

MessagesBackend _parseBackend(String raw) => switch (raw) {
  'jxa' => MessagesBackend.jxa,
  'ax' => MessagesBackend.ax,
  _ => MessagesBackend.auto,
};

int _parseNonNegativeInt(String raw, String optionName) {
  final value = int.tryParse(raw);
  if (value == null || value < 0) {
    throw FormatException('--$optionName must be a non-negative integer.');
  }
  return value;
}
