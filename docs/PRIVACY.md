# Privacy and local data

Mail is designed as a local macOS client. It has no hosted Mail backend and does not require an account beyond the Gmail account you choose to connect.

## Data flow

```text
Your Mac ⇄ Google OAuth and Gmail API
    ↓
Keychain: refresh token
SQLite: normalized mail cache, FTS index, sync state, recipient directory
```

Gmail authorization opens in the Mac's system browser. API requests then travel directly between the app and Google. The app's local cache supports fast launch, offline reading of synced content, and instant search.

## Stored on the Mac

- OAuth refresh token in macOS Keychain.
- Normalized Gmail messages, headers, labels, and snippets in SQLite.
- Full-text search terms and compact thread summaries in SQLite/FTS5.
- Gmail history cursor and sync metadata.
- Recipient names and addresses found in sent correspondence.
- Draft and local workflow state required by the interface.

Selected attachment bytes are read when needed to construct or display a message. They are not embedded in source code or repository fixtures.

## Google access

Mail requests `https://www.googleapis.com/auth/gmail.modify`. That scope supports reading, sending, archiving, starring, and read-state changes. The app does not request permanent-delete access.

You can revoke access at any time from your Google Account's third-party access settings. Disconnecting inside Mail removes the saved refresh token from Keychain; local cache removal should be treated as a separate destructive action.

## Public repository data

The repository contains only fictional mail and reserved `.example` addresses. It excludes:

- OAuth client JSON and environment files;
- access and refresh tokens;
- Gmail databases and WAL files;
- real messages, recipients, attachments, and diagnostics;
- screenshots from connected accounts;
- generated local app bundles and benchmark data.

If you report an issue, replace all personal content with a fictional reproduction before posting it publicly.
