// Copyright 2026 Kevin Moore. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

export 'src/messages_client.dart'
    show
        AxMessagesClient,
        HybridMessagesClient,
        JxaMessagesClient,
        MessagesClient,
        MessagesClientException,
        ProcessRunner;
export 'src/models.dart'
    show
        ArchiveConversationResult,
        BlockConversationResult,
        ConversationSummary,
        DomHealthReport,
        MessagesBackend,
        SendMessageResult,
        SpamConversationSummary,
        ThreadMessage,
        ThreadReadResult,
        checkUnreadSafety,
        extractConversationId,
        filterConversations,
        findMatchingConversations;
