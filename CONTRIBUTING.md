# Contributing to Mail

Focused bug fixes, performance improvements, accessibility work, and changes that preserve Mail's intentionally narrow product shape are welcome.

## Before opening an issue

- Search existing issues and confirm the behavior on the latest `main` build.
- Remove names, addresses, subjects, message bodies, OAuth values, database paths, and screenshots from real accounts.
- Include the macOS version, Mail version, exact keys or clicks, expected result, and actual result.
- Use GitHub private vulnerability reporting for security issues.

## Local setup

Mail requires macOS 14 or later and Apple's command-line developer tools.

```bash
git clone https://github.com/bradymoore1010/swaggerhuman.git
cd swaggerhuman
./scripts/test.sh
./scripts/build-app.sh
open "Mail.app"
```

The default inbox is fictional and works without Gmail credentials. Real-provider testing is separate and must use your own account and OAuth client.

## Change guidelines

- Keep the app native and keyboard-first. Avoid web runtimes, hosted services, calendar/task features, and unrelated dashboards.
- Preserve the first-contact versus ongoing-correspondence thread-opening rule.
- Keep cached UI usable without a network request; do not move Gmail, SQLite, MIME, indexing, or file work onto the main actor.
- Add deterministic coverage for behavior changes and rerun the relevant performance check for hot-path changes.
- Use fictional `.example` addresses and invented message copy in tests, docs, prototypes, and media.
- Keep pull requests small enough to review and explain the user-visible result first.

## Required checks

```bash
./scripts/test.sh
./scripts/build-app.sh
./scripts/check-public-tree.sh
git diff --check
```

For inbox, search, thread, cache, or editor performance work:

```bash
./scripts/benchmark.sh contributor-check 3
./scripts/benchmark-launch.sh contributor-launch 5
```

For launch-film changes:

```bash
cd launch-video
npm install
npm run lint
npm run render:hero
```

## Pull requests

Describe the outcome, why the change belongs in Mail, tests run, performance impact, and any privacy or security implications. Screenshots must use only the included fictional inbox.

By contributing, you agree that your contribution is licensed under the MIT License and that you will follow the [Code of Conduct](CODE_OF_CONDUCT.md).
