# Changelog

All notable changes to Mail are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses semantic versioning.

## [Unreleased]

## [1.0.0] - 2026-09-03

### Added

- Native SwiftUI macOS inbox, focused conversation reader, compose, reply, search, mailboxes, and command palette.
- Browser-based Gmail OAuth with PKCE, refresh-token storage in Keychain, Gmail history synchronization, and a local SQLite/FTS5 cache.
- Gmail-backed archive, star, read state, reply, formatted MIME send, inline images, and file attachments.
- Gmail-wide recipient directory built from all sent correspondence.
- Correspondence-aware thread opening: reader-only for untouched conversations and a ready reply composer for ongoing conversations.
- Native AppKit editor behavior for selection, deletion, lists, indentation, drag-and-drop attachments, and keyboard commands.
- Deterministic 10,000-thread performance harness, paired regression comparisons, launch benchmark, and sustained-use soak test.
- Frosted-glass production interface, interactive local HTML prototype, public hero artwork, and a reproducible 19-second Remotion launch film.

### Performance

- All 19 established interaction metrics stayed within the strict `+5%` regression gate.
- Frosted-glass warm launch measured `422.672 ms` at p95 in the matched production comparison.
- Accepted sustained-use runs recorded zero main-thread tasks above 50 ms and no resident-memory growth.

[Unreleased]: https://github.com/bradymoore1010/mail/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/bradymoore1010/mail/releases/tag/v1.0.0
