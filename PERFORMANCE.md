# Native speed contract

Keyboard Mail should feel finished before the network has a chance to be slow. The current build establishes the interaction path; the Gmail phase must preserve it with a local-first data layer.

## Principles taken from Mitchell Hashimoto's Superlogical posts

- Treat Dock bounce count as a user-visible startup metric, not a cosmetic detail. Hashimoto described one bounce as the point that became achievable with SSD-era apps: [half-bounce discussion](https://x.com/mitchellh/status/2093700021166485893).
- Remove staged loading views from startup unless a delay actually needs explanation. He called out view-hierarchy frame reconciliation as work that should stay off the startup path: [startup loading-state critique](https://x.com/mitchellh/status/2095000363674042655).
- Tune on weak hardware, not only the development machine. His test target is a 2020 Intel MacBook Air with an i3 and 8 GB of memory: [worst-case hardware post](https://x.com/mitchellh/status/2094494569857777750).
- Native implementation is part of the performance strategy. Superlogical's published split is Swift on macOS, Go on the server, and Zig for its high-performance core: [stack post](https://x.com/mitchellh/status/2095196756153954365).
- Fast synchronization can use a compact protocol and replica-style local state, but Keyboard Mail should not copy architecture it does not need. Gmail is the server here; the applicable lesson is to make local state authoritative for the interface and reconcile remotely afterward: [Superlogical speed demo](https://x.com/mitchellh/status/2093451043661316217).

## Applied in this build

- Native SwiftUI shell with AppKit `NSTextView` for the typing, cursor, selection, undo, deletion, and keyboard-command path.
- Optimized Release packaging rather than a Debug executable.
- No startup spinner, placeholder sequence, authentication request, or network dependency. The first frame is complete local UI.
- A six-row initial inbox materialization window that grows incrementally as the user scrolls, with stable row identities so search and mailbox changes do not rebuild the entire list.
- Direct keyboard handling with no web runtime or JavaScript bridge.
- Short, zero-bounce transitions: 100 ms for app layers and 120–160 ms for thread changes. Reduce Motion removes them.
- Native file importer and drag target; attachment metadata is added only after selection and file bytes are not loaded into view state.
- Command-K and inbox search use an immutable in-memory index for immediate feedback and ID-only SQLite FTS5 queries for the durable Gmail cache.
- Command-K keeps a fixed result viewport, ignores key-repeat activation, and captures the first query keystroke even before SwiftUI finishes moving focus.
- Gmail cache startup reads compact thread summaries first. Full message bodies hydrate only when opened, and reusable WebKit/editor pools remove repeated setup work.
- Embedded HTML forwards wheel gestures to the thread scroller and supports measured bodies up to 120,000 points instead of clipping long messages.
- Gmail, SQLite, MIME, indexing, and attachment metadata work remain off the main actor. User actions update local state first and roll back if Gmail rejects the operation.

## Measurable release budgets

The checked-in release harness measures these on a deterministic 10,000-thread mailbox. See [docs/PERFORMANCE_REPORT.md](docs/PERFORMANCE_REPORT.md) for the current results. A lower-end supported Mac remains an important additional validation target.

- Launch to usable cached inbox: under 500 ms and no more than a half Dock bounce.
- Key press to editor paint: under one 60 Hz frame at the 95th percentile.
- Command-K visible and focused: under 50 ms.
- Local search result update: under 50 ms at 10,000 threads.
- Compact-to-expanded message transition: 160 ms or less, with content ready before animation starts.
- Attachment command to AppKit picker request: under 100 ms; attachment bytes remain lazy until send or explicit open.
- Main-thread stalls: none above 50 ms during launch, typing, scrolling, opening a thread, or syncing.

## Gmail architecture required to keep those budgets

Render SQLite data first, start Gmail history sync afterward, coalesce repository changes, and never parse MIME or index message bodies on the main actor. Outgoing actions update the local model optimistically and reconcile in the background. A slow or unavailable Gmail connection must affect freshness, not cursor response, navigation, search, or the first usable frame.
