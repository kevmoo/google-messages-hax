Read-only macOS automation and CLI for the Google Messages Chrome PWA using JXA
Apple Events (`osascript`) and native `ApplicationServices` Accessibility
(`AXUIElement`).

## Overview

`google_messages_hax` inspects your running Google Messages Chrome PWA in the
background without focusing the window or marking unread conversations as read:

1. **Zero-click sidebar & unread inspection**: Reads conversation IDs, contact
   and group names, full latest-message snippets, relative timestamps, and
   `UNREAD` / `ACTIVE` / `PINNED` state directly from the DOM or Accessibility
   tree.
2. **Strict unread protection**: By default, `gmessages read <query>` refuses to
   click into any conversation marked `UNREAD` (or switch away from an unread
   active thread), returning the sidebar's full latest-message snippet instead
   unless `--allow-mark-read` is explicitly passed.
3. **Background thread reading & restoration**: For already-read conversations,
   switches to the target conversation in the background, optionally scrolls up
   (`--scroll-pages`) to load older message history, and restores the previously
   selected conversation.
4. **Hybrid backend (`--backend auto|jxa|ax`)**: Uses fast JXA JavaScript
   execution (`View > Developer > Allow JavaScript from Apple Events`) when
   enabled and automatically falls back to native macOS Accessibility (`swift`
   `AXUIElement` with `AXManualAccessibility`) when JXA JS is turned off.

## CLI Usage

List recent conversations (preserving all unread state):

```sh
dart run bin/gmessages.dart list -n 15
```

List only unread conversations:

```sh
dart run bin/gmessages.dart list --unread-only
```

Search loaded conversations (or paginate older sidebar batches first):

```sh
dart run bin/gmessages.dart search "Acme Dental" --load-more 1
```

Read messages from the currently open conversation (zero clicks):

```sh
dart run bin/gmessages.dart active --scroll-pages 1
```

Read messages from an already-read conversation (or safely inspect the snippet
of an unread conversation without marking it read):

```sh
dart run bin/gmessages.dart read "Alex and Sam" --scroll-pages 1
```

Audit conversations in the "Spam & blocked" modal (including extracted URLs):

```sh
dart run bin/gmessages.dart spam
```
