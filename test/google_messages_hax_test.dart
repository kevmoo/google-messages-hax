// Copyright 2026 Kevin Moore. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

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
}
