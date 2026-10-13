// Copyright 2026 Kevin Moore. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:google_messages_hax/google_messages_hax.dart';
import 'package:test/test.dart';

void main() {
  const activeReadConv = ConversationSummary(
    id: 'thread-active',
    href: '/web/conversations/thread-active',
    name: '(555) 010-1234',
    snippet: 'You: sounds good',
    timestamp: '2:10 PM',
    isUnread: false,
    isActive: true,
  );

  const unreadConv = ConversationSummary(
    id: 'thread-unread',
    href: '/web/conversations/thread-unread',
    name: 'Acme Dental',
    snippet: 'Good morning, we have appointments available Tuesday at 9 am.',
    timestamp: '10:15 AM',
    isUnread: true,
    isActive: false,
  );

  const otherReadConv = ConversationSummary(
    id: 'thread-202',
    href: '/web/conversations/thread-202',
    name: 'Alex and Sam',
    snippet: 'You: bumped to noon',
    timestamp: '1:33 PM',
    isUnread: false,
    isActive: false,
  );

  group('extractConversationId', () {
    test('extracts ID from relative and full conversation URLs', () {
      expect(
        extractConversationId('/web/conversations/thread-202'),
        'thread-202',
      );
      expect(
        extractConversationId(
          'https://messages.google.com/web/conversations/thread-active',
        ),
        'thread-active',
      );
      expect(extractConversationId(''), isEmpty);
    });
  });

  group('filterConversations & findMatchingConversations', () {
    final all = [activeReadConv, unreadConv, otherReadConv];

    test('filters unread-only and search queries', () {
      final unread = filterConversations(all, unreadOnly: true);
      expect(unread.map((c) => c.id).toList(), ['thread-unread']);

      final searched = filterConversations(
        all,
        query: 'appointments available',
      );
      expect(searched.map((c) => c.id).toList(), ['thread-unread']);

      final limited = filterConversations(all, limit: 2);
      expect(limited, hasLength(2));
    });

    test('prefers exact ID or name match over substring match', () {
      final byId = findMatchingConversations(all, 'thread-202');
      expect(byId.single.name, 'Alex and Sam');

      final bySubstring = findMatchingConversations(all, 'acme');
      expect(bySubstring.single.id, 'thread-unread');
    });
  });

  group('checkUnreadSafety', () {
    test(
      'blocks opening an unread conversation unless allowMarkRead is set',
      () {
        final reason = checkUnreadSafety(
          target: unreadConv,
          activeConversation: activeReadConv,
          allowMarkRead: false,
        );
        expect(reason, isNotNull);
        expect(reason, contains('UNREAD'));

        final allowed = checkUnreadSafety(
          target: unreadConv,
          activeConversation: activeReadConv,
          allowMarkRead: true,
        );
        expect(allowed, isNull);
      },
    );

    test('allows reading an already-read conversation when active is read', () {
      final reason = checkUnreadSafety(
        target: otherReadConv,
        activeConversation: activeReadConv,
        allowMarkRead: false,
      );
      expect(reason, isNull);
    });

    test('blocks switching away if currently active thread is unread', () {
      const unreadActive = ConversationSummary(
        id: 'EgUnreadActive',
        href: '/web/conversations/EgUnreadActive',
        name: 'Active Unread Thread',
        snippet: 'New message',
        timestamp: 'Now',
        isUnread: true,
        isActive: true,
      );
      final reason = checkUnreadSafety(
        target: otherReadConv,
        activeConversation: unreadActive,
        allowMarkRead: false,
      );
      expect(reason, isNotNull);
      expect(reason, contains('Currently active conversation'));
    });
  });

  group('HybridMessagesClient fallback', () {
    test('falls back from JXA to AX when AppleScript JS is disabled', () async {
      const jxa = _FakeMessagesClient(
        error: MessagesClientException(
          'JXA execution failed: Error: Executing JavaScript through '
          'AppleScript is turned off.',
        ),
      );
      const ax = _FakeMessagesClient(
        conversations: [activeReadConv, unreadConv],
      );
      final hybrid = HybridMessagesClient(jxaClient: jxa, axClient: ax);

      final list = await hybrid.listConversations();
      expect(list.map((c) => c.id).toList(), [
        'thread-active',
        'thread-unread',
      ]);
    });
  });

  group('JxaMessagesClient with fake ProcessRunner', () {
    final conversationsJson = jsonEncode([
      activeReadConv.toJson(),
      unreadConv.toJson(),
      otherReadConv.toJson(),
    ]);

    test('blocks sendMessage to unread thread unless allowMarkRead is set', () {
      final client = JxaMessagesClient(
        processRunner: (exe, args) async =>
            ProcessResult(1, 0, conversationsJson, ''),
      );

      expect(
        () => client.sendMessage('Acme Dental', 'STOP'),
        throwsA(
          isA<MessagesClientException>().having(
            (e) => e.message,
            'message',
            contains('UNREAD'),
          ),
        ),
      );
    });

    test('sendMessage --dry-run validates without invoking AXPress', () async {
      final calls = <String>[];
      final client = JxaMessagesClient(
        processRunner: (exe, args) async {
          calls.add(exe);
          return ProcessResult(1, 0, conversationsJson, '');
        },
      );

      final res = await client.sendMessage(
        'Alex and Sam',
        'STOP',
        dryRun: true,
      );
      expect(res.dryRun, isTrue);
      expect(res.sent, isFalse);
      expect(res.conversation.id, 'thread-202');
      expect(calls, ['osascript']);
    });

    test(
      'sendMessage executes JXA input, Swift AXPress, and restores active',
      () async {
        final calls = <String>[];
        final client = JxaMessagesClient(
          processRunner: (exe, args) async {
            calls.add(exe);
            if (exe == 'swift') {
              return ProcessResult(2, 0, 'PRESSED:0\n', '');
            }
            final script = args.last;
            if (script.contains('window.__gmessagesHax.listConversations()')) {
              return ProcessResult(1, 0, conversationsJson, '');
            }
            if (script.contains('READY_TO_PRESS')) {
              return ProcessResult(1, 0, 'READY_TO_PRESS\n', '');
            }
            return ProcessResult(
              1,
              0,
              '/web/conversations/thread-active\n',
              '',
            );
          },
        );

        final res = await client.sendMessage('Alex and Sam', 'STOP');
        expect(res.sent, isTrue);
        expect(res.restoredActiveHref, '/web/conversations/thread-active');
        expect(calls, ['osascript', 'osascript', 'swift', 'osascript']);
      },
    );

    test('archiveConversations supports dry-run and live archive', () async {
      final client = JxaMessagesClient(
        processRunner: (exe, args) async {
          final script = args.last;
          if (script.contains('window.__gmessagesHax.listConversations()')) {
            return ProcessResult(1, 0, conversationsJson, '');
          }
          return ProcessResult(
            1,
            0,
            jsonEncode({
              '/web/conversations/thread-202': 'ARCHIVED',
              '/web/conversations/thread-unread': 'ARCHIVED',
            }),
            '',
          );
        },
      );

      final dry = await client.archiveConversations([
        'thread-202',
        'Acme Dental',
      ], dryRun: true);
      expect(dry.every((r) => r.dryRun && !r.archived), isTrue);

      final live = await client.archiveConversations([
        'thread-202',
        'Acme Dental',
      ]);
      expect(live.map((r) => r.conversation.id), [
        'thread-202',
        'thread-unread',
      ]);
      expect(live.every((r) => r.archived), isTrue);
    });

    test(
      'checkDomHealth parses selector counts and missing selectors',
      () async {
        final client = JxaMessagesClient(
          processRunner: (exe, args) async => ProcessResult(
            1,
            0,
            jsonEncode({
              'ok': true,
              'selectorCounts': {
                'mws-conversation-list-item': 25,
                'a[data-e2e-conversation]': 25,
              },
              'missingRequiredSelectors': <String>[],
            }),
            '',
          ),
        );

        final report = await client.checkDomHealth();
        expect(report.ok, isTrue);
        expect(report.selectorCounts['mws-conversation-list-item'], 25);
        expect(report.missingRequiredSelectors, isEmpty);
      },
    );
  });
}

final class _FakeMessagesClient implements MessagesClient {
  final List<ConversationSummary> conversations;
  final MessagesClientException? error;

  const _FakeMessagesClient({this.conversations = const [], this.error});

  @override
  Future<List<ConversationSummary>> listConversations({
    int loadMorePages = 0,
  }) async {
    if (error != null) throw error!;
    return conversations;
  }

  @override
  Future<ThreadReadResult> readActiveThread({int scrollUpPages = 0}) async {
    if (error != null) throw error!;
    return ThreadReadResult(
      conversation: conversations.firstOrNull,
      messages: const [],
      backendUsed: MessagesBackend.ax,
    );
  }

  @override
  Future<ThreadReadResult> readThread(
    String queryOrId, {
    int scrollUpPages = 0,
    int loadMorePages = 0,
    bool allowMarkRead = false,
  }) async {
    if (error != null) throw error!;
    return ThreadReadResult(
      conversation: conversations.firstOrNull,
      messages: const [],
      backendUsed: MessagesBackend.ax,
    );
  }

  @override
  Future<List<SpamConversationSummary>> listSpamAndBlocked({
    int scrollPages = 3,
  }) async {
    if (error != null) throw error!;
    return const [];
  }

  @override
  Future<SendMessageResult> sendMessage(
    String queryOrId,
    String text, {
    int loadMorePages = 0,
    bool allowMarkRead = false,
    bool dryRun = false,
  }) async {
    if (error != null) throw error!;
    return SendMessageResult(
      conversation: conversations.first,
      text: text,
      dryRun: dryRun,
      sent: !dryRun,
      backendUsed: MessagesBackend.ax,
    );
  }

  @override
  Future<List<ArchiveConversationResult>> archiveConversations(
    List<String> queriesOrIds, {
    int loadMorePages = 0,
    bool dryRun = false,
  }) async {
    if (error != null) throw error!;
    return const [];
  }

  @override
  Future<DomHealthReport> checkDomHealth() async {
    if (error != null) throw error!;
    return const DomHealthReport(
      ok: true,
      selectorCounts: {},
      missingRequiredSelectors: [],
      backendUsed: MessagesBackend.ax,
    );
  }
}
