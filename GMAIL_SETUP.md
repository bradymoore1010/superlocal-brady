# Connect Keyboard-First Mail to Gmail

Yes, this can be a working Gmail client without adding a hosted backend. The first production version should keep mail and credentials on the Mac: Google OAuth in the system browser, refresh tokens in Keychain, Gmail API sync, and a local SQLite search index.

## What is live in version 1.0

- Browser-based OAuth Authorization Code flow with PKCE, random state, and a temporary loopback callback.
- Refresh-token storage in macOS Keychain and automatic access-token refresh.
- First sync into a local SQLite/WAL cache, followed by Gmail `history.list` incremental sync with full-sync recovery.
- Native inbox, thread, compose, reply, archive, star, and read/unread actions backed by Gmail.
- Local instant search plus remote Gmail search for conversations outside the recent local cache.
- Gmail-wide recipient autocomplete built from every conversation in Sent, with a complete refresh on `Sync now`.
- MIME sending for formatted text, nested list indentation, inline images, and ordinary attachments.

## One-time Google setup

1. Create or select a Google Cloud project and enable the Gmail API.
2. Configure the OAuth consent screen for an External audience.
3. Publish the app to In production for daily use. Leaving it in Testing makes Gmail refresh tokens expire after seven days.
4. Create an OAuth client with application type Desktop app.
5. Download the OAuth client JSON, click `Connect Gmail` in Mail, and choose that JSON file.

For one-person use, Google allows an unverified app with fewer than 100 users. Google will show an unverified-app warning during consent; formal verification is only necessary if the app is distributed more broadly. See Google's [OAuth verification exceptions](https://support.google.com/cloud/answer/13464323) and [audience and publishing-status guidance](https://support.google.com/cloud/answer/15549945).

## Connection design

- Open Google's authorization page in the Mac's default browser.
- Use Authorization Code with PKCE, a random `state` value, and a temporary loopback callback such as `http://127.0.0.1:<random-port>`.
- Request only `https://www.googleapis.com/auth/gmail.modify`. This is enough to read, send, archive, star, and change read state without granting permanent deletion.
- Exchange the returned code for tokens and save the refresh token in macOS Keychain. Never put tokens in source files or `UserDefaults`.
- Perform a first full sync with `messages.list` and batched `messages.get`, then store the newest Gmail `historyId`.
- Perform later incremental syncs with `history.list`; fall back to a full sync if Gmail says the stored history ID is too old.
- Cache normalized threads and message text locally. Use SQLite FTS5 for instant Command-K and inbox search once real mail volume replaces the fixture.
- Build outgoing MIME messages locally and send them with `messages.send`. Read user-selected attachments only while constructing that message.

## Gmail performance contract

- The first usable window must come entirely from the local SQLite cache. OAuth refresh, Gmail requests, reconciliation, and attachment fetches must never block launch.
- Start incremental `history.list` sync only after the cached inbox is visible. Apply changes to the repository in batches so one network page does not trigger hundreds of SwiftUI updates.
- Keep full message bodies and attachment bytes lazy. Inbox rows and Command-K need normalized headers, snippets, labels, dates, and attachment metadata, not every byte of every message.
- Search the local FTS5 index while typing. Network search may be an explicit fallback, but it must not replace or stall local results.
- Keep the Gmail API and database behind isolated actors, then publish compact view models on the main actor. Parsing, MIME construction, indexing, and file hashing stay off the main actor.
- Preserve the current instant local action. Archive, star, read/unread, reply, and send should update the UI optimistically, persist locally, then reconcile with Gmail in the background with a visible failure state if needed.

Google's primary references: [OAuth for native apps](https://developers.google.com/identity/protocols/oauth2/native-app), [Gmail API scopes](https://developers.google.com/workspace/gmail/api/auth/scopes), and [Gmail client synchronization](https://developers.google.com/workspace/gmail/api/guides/sync).

The credential creation and Gmail consent click are the only user-owned steps. Creating an OAuth client grants persistent access, so those steps should happen only when you are ready to authorize them.
