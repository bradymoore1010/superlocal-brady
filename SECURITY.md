# Security policy

## Supported version

Security fixes are applied to the latest release on `main`.

| Version | Supported |
| --- | --- |
| 1.x | Yes |
| Earlier | No |

## Report a vulnerability

Please use GitHub's private vulnerability reporting for this repository. Do not open a public issue with an exploit, OAuth configuration, token, message content, database, or screenshot from a real inbox.

Include the affected version, macOS version, reproduction steps, impact, and a minimal sanitized proof of concept. You should receive an acknowledgement within seven days. A fix and disclosure timeline will be coordinated according to severity.

## Security boundaries

- Gmail authorization uses OAuth Authorization Code with PKCE, a random state value, and a temporary loopback callback.
- Refresh tokens are stored in macOS Keychain, not source files or `UserDefaults`.
- The requested `gmail.modify` scope supports reading, sending, archiving, starring, and read-state changes without permanent-delete access.
- Mail data and full-text search indexes are stored locally in SQLite.
- HTML email is rendered through WebKit with the app's message-rendering policy; received scripts are not treated as application code.
- The app has no hosted backend. Gmail API requests go from the Mac to Google.

## Repository hygiene

Never commit or attach OAuth JSON, access or refresh tokens, `.env` files, SQLite databases, real message content, recipient exports, private diagnostics, or screenshots from a real account. The repository's ignore rules cover common local artifacts, but every contribution must still be reviewed before publication.
