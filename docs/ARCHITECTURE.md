# Mail architecture

Mail is a single native macOS application. Its architecture is deliberately local-first: the interface reads cached state immediately, then synchronizes with Gmail without blocking keyboard input or launch.

## System map

```text
KeyboardFirstMailApp
        ↓
   AppShellView
        ↓
     MailStore  ← keyboard commands, search, compose, triage
      ↙     ↘
SQLiteMailRepository     GmailIntegration
 summaries + FTS5        OAuth + sync + mutations
      ↑                       ↓
 hydrated threads         GmailAPIClient
                              ↓
                           Gmail API
```

## Interface layer

SwiftUI owns the window, sidebar, inbox, command palette, thread reader, connection flow, compose sheet, and settings. Two native components handle interaction where system behavior matters:

- `NativeMailTextView`, an AppKit `NSTextView`, provides macOS caret, selection, undo, deletion, list continuation, indentation, link, and inline-image behavior.
- `MailHTMLBodyView`, backed by a pooled `WKWebView`, renders received HTML and forwards scroll gestures to the conversation surface.

The sidebar occupies the full window height. The main region switches between a compact inbox and one focused conversation rather than keeping both hierarchies alive.

## State and actions

`MailStore` is the main-actor owner of user-visible state. It keeps stable thread IDs, mailbox membership, selection, search results, composer state, undo windows, and transient status. It does not perform Gmail requests or SQLite scans on the main actor.

Archive, star, read-state, send, and similar actions update the local model immediately. The corresponding Gmail mutation runs in the background. A failed remote action restores the previous local state and surfaces an error.

## Correspondence-aware opening

Thread opening is based on actual message direction:

- If the conversation contains no sent message from the connected account, Mail opens the latest incoming message in reader mode. The reply editor is created only after `R` or the Reply button.
- If the conversation already contains a sent message from the connected account, Mail opens the latest incoming message and prepares the inline reply composer.

The rule is computed from parsed message headers rather than sender display names.

## Gmail integration

`GmailIntegration` coordinates an actor-isolated `GmailAPIClient` and `SQLiteMailRepository`.

- OAuth Authorization Code with PKCE opens in the system browser and returns through a random loopback port.
- `GmailCredentialStore` saves refresh tokens in macOS Keychain.
- A cached mailbox is loaded before OAuth refresh or network work.
- Initial synchronization lists and hydrates Gmail data in bounded groups.
- Later synchronization uses Gmail `history.list`; an expired history ID falls back to a full reconciliation.
- MIME building, message parsing, attachment reads, indexing, and file hashing remain off the main actor.
- Remote Gmail search supplements local FTS5 results for mail outside the recent cache.

## Recipient directory

`GmailRecipientDirectoryBuilder` scans every thread containing sent mail and extracts normalized addresses from From, To, Cc, Bcc, and Reply-To headers. The job is asynchronous, rate-aware, and cached in SQLite. The composer can use the previous directory immediately while a refresh continues.

## Local persistence

`SQLiteMailRepository` is actor-isolated and opens SQLite in full-mutex mode. It stores:

- compact thread summaries for launch and inbox rows;
- full messages for on-demand thread hydration;
- mailbox and label state;
- draft and sync metadata;
- the Gmail history cursor;
- a recipient-directory snapshot;
- FTS5 search records.

Compact summaries avoid decoding full HTML and message bodies at launch. The reader hydrates one conversation when opened.

## Performance model

The performance harness seeds a deterministic 10,000-thread SQLite mailbox. Instrumentation measures launch-to-useful-frame, keyboard actions, inbox materialization, search, FTS, cache loads, thread opening, reply typing, main-queue delay, run-loop CPU work, and memory.

Relative release checks use counterbalanced baseline/current pairs and a strict `+5%` median paired p95 ceiling. Sustained-use checks retain absolute tail limits for main-thread stalls and memory. See [PERFORMANCE_REPORT.md](PERFORMANCE_REPORT.md).

## Repository map

| Path | Purpose |
| --- | --- |
| `Sources/KeyboardFirstMail/` | Native app source |
| `Tests/` | Deterministic behavior runners |
| `Benchmarks/` | 10,000-thread benchmark and fixture seeding |
| `scripts/` | Build, test, benchmark, soak, and release tooling |
| `AppResources/` | Bundle metadata and app icon assets |
| `v.2/` | Standalone fictional-data interaction prototype |
| `launch-video/` | Remotion source for launch film and public artwork |
| `docs/assets/` | Reviewed public media generated from fictional data |
