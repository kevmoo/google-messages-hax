macOS automation and CLI for the Google Messages Chrome PWA using JXA Apple
Events (`osascript`) and native `ApplicationServices` Accessibility
(`AXUIElement`), designed around strict unread-state preservation.

1. **Zero-click sidebar & unread inspection**: Reads conversation IDs, contact
   and group names, full latest-message snippets, relative timestamps, and
   `UNREAD` / `ACTIVE` / `PINNED` state directly from the DOM or Accessibility
   tree.
2. **Strict unread protection**: By default, `gmessages read` and
   `gmessages send` refuse to click into any conversation marked `UNREAD` (or
   switch away from an unread active thread), returning the sidebar's full
   latest-message snippet instead unless `--allow-mark-read` is explicitly
   passed.
3. **Background thread reading & restoration**: For already-read conversations,
   switches to the target conversation in the background, optionally scrolls up
   (`--scroll-pages`) to load older message history, and restores the previously
   selected conversation.
4. **Sidebar-native mutations (`archive`, `mark-unread`, `mark-read`)**: Uses
   each sidebar row's options menu (`button.menu-button`) so conversations can
   be archived or toggled between read and unread without opening the thread.
5. **Hybrid background SMS sending (`send`)**: Populates the compose box via JXA
   `InputEvent` and presses the `Send SMS` button via native macOS Accessibility
   (`kAXPressAction`) so Chromium receives a hardware-trusted click
   (`event.isTrusted === true`) in the background.

## Requirements & Constraints

- **macOS + Google Chrome only**: This package invokes macOS
  `/usr/bin/osascript` (JXA targeting `com.google.Chrome`) and `/usr/bin/swift`
  (`ApplicationServices` / `AXUIElement`). Even when Google Messages is
  installed as a standalone Chrome PWA (`Messages.app` / `app_mode_loader`), its
  window and tabs are hosted inside the main `Google Chrome` process via
  `RemoteCocoa`. Other browsers (Safari, Firefox, Arc) and non-macOS platforms
  are not supported.
- **Active Google Messages session**: A `https://messages.google.com/web` tab or
  installed Chrome PWA window must already be open and paired with your phone.
- **Chrome Apple Events JS setting (recommended)**: For full functionality,
  enable **View > Developer > Allow JavaScript from Apple Events** in Google
  Chrome.
- **macOS Privacy permissions**: Your terminal or agent host must be granted:
  - **System Settings > Privacy & Security > Automation** (to allow `osascript`
    to control `Google Chrome`).
  - **System Settings > Privacy & Security > Accessibility** (required for the
    `ax` fallback backend and for `gmessages send` to set
    `AXManualAccessibility` and invoke `AXPress` on `Send SMS`).
- **Why `send` requires both JXA and Accessibility (`AXPress`)**: Google
  Messages Web ignores untrusted synthetic DOM `.click()` events
  (`event.isTrusted === false`) on `<mw-message-send-button>`, while setting the
  `AXTextArea` value via Accessibility alone does not fire Angular's internal
  `InputEvent` listener that enables the button. `gmessages send` combines JXA
  (`InputEvent` composition) with Swift `AXUIElementPerformAction`
  (`kAXPressAction`).

### Backend Capability Matrix (`--backend auto|jxa|ax`)

| Operation                                            | `jxa` Backend (Apple Events JS Enabled)                     | `ax` Fallback (Apple Events JS Off)                |
| :--------------------------------------------------- | :---------------------------------------------------------- | :------------------------------------------------- |
| `list` / `search` (including `--load-more`)          | Supported (includes conversation IDs & `href`s)             | Supported (positional `ax-<n>` IDs)                |
| `active` (read currently selected thread)            | Supported (includes `--scroll-pages`)                       | Supported (currently visible messages)             |
| `read` (already-read non-active thread)              | Supported (switches in background & restores active thread) | Snippet-only (strict zero-click mode)              |
| `read` (`UNREAD` thread without `--allow-mark-read`) | Snippet-only (preserves unread state)                       | Snippet-only (preserves unread state)              |
| `spam` (audit `Spam & blocked` modal + URLs)         | Supported                                                   | Not supported                                      |
| `archive` / `mark-unread` / `mark-read`              | Supported                                                   | Not supported                                      |
| `send` (background SMS/RCS reply)                    | Supported (uses JXA `InputEvent` + Swift `AXPress`)         | Not supported                                      |
| `doctor` (zero-click selector health check)          | Supported (audits live DOM selectors)                       | Supported (verifies `AXWebArea` conversation list) |

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

Validate live DOM selector health (zero clicks) before running automation:

```sh
dart run bin/gmessages.dart doctor
```

Send a message (e.g., `"STOP"`) using hybrid JXA `InputEvent` composition +
Swift `AXPress` on `Send SMS` (enforces unread safety unless `--allow-mark-read`
is set, and supports `--dry-run`):

```sh
dart run bin/gmessages.dart send "(555) 010-1234" "STOP" --dry-run
```

Archive one or more conversations directly from the sidebar options menu without
opening them:

```sh
dart run bin/gmessages.dart archive "(555) 010-1234" "thread-202" --dry-run
```

Mark a conversation as unread or read via the sidebar options menu:

```sh
dart run bin/gmessages.dart mark-unread "(555) 010-1234" --dry-run
```
