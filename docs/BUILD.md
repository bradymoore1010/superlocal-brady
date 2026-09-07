# Build Superlocal on macOS

Requirements: Bun 1.4.0 or newer, Node.js 22.18 or newer for the web tests, and Apple's command-line developer tools for the Mac wrapper. The wrapper currently expects Bun at `/opt/homebrew/bin/bun` and uses ports 5178 and 8790. HTTP(S) links open in Chrome.

From the repository root:

```sh
bun --no-env-file install --frozen-lockfile
bun --no-env-file run typecheck
bun --no-env-file run build
bun --no-env-file run typecheck:host
bun --no-env-file run typecheck:mock
bun --no-env-file run build:web
bun --no-env-file run test:web
INBOX_TEST_LIVE=false bun --no-env-file run test:api
INBOX_TEST_LIVE=false bun --no-env-file test ./packages/inbox-sdk/tests/provider.test.ts --test-name-pattern 'gmail deterministic native peer'
bun --no-env-file run build:macos
```

The last command creates `build/Superlocal.app` with the current icon and light titlebar. It ad-hoc signs the bundle; it does not install, launch, or notarize it. Dependencies must already be installed. The wrapper launches the local development host, matching the current personal setup.

The app keeps its configuration and mail data in `~/Library/Application Support/Superlocal` and logs in `~/Library/Logs/Superlocal`. A first run creates a mock configuration; Gmail requires your own local provider configuration. Do not run a second copy while Superlocal is already using the same ports and data directory. No account configuration, credentials, or real mail are included in this repository.

The full optional provider suite is `INBOX_TEST_LIVE=false bun --no-env-file run test:provider`. The imported snapshot currently has 12 failing Outlook/IMAP checks. CI covers this personal Gmail setup with the web, API, and Gmail provider suites; it does not claim Outlook/IMAP compatibility.
