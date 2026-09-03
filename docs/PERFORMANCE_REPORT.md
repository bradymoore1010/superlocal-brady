# Performance benchmark report

Status: Ready to share.

The September 3 production build passes the strict post-feature regression gate: all 19 established interaction metrics remain within 5% of the pre-feature build. The largest median paired p95 regression was 1.843%, leaving 3.157 percentage points of headroom. All six sustained-use percentile metrics also improved in the matched long-run comparison. Launch, interaction, sustained-use, build, signing, and behavior checks pass.

## Frosted-glass production confirmation

The approved frosted-glass interface was applied as a visual-only release after the feature certification below. Twenty additional matched warm-launch pairs compared the preserved pre-glass app with the signed frosted candidate on the same 10,000-thread cache.

| Warm launch measure | Pre-glass | Frosted production | Gate | Result |
| --- | ---: | ---: | ---: | --- |
| p75 first useful frame | 415.621 ms | 418.847 ms | 500 ms | Pass |
| p95 first useful frame | 419.928 ms | 422.672 ms | 1,000 ms | Pass |
| Median paired change | — | +1.055688% | <= +5.000% | Pass |

Three additional full interaction batches passed every established absolute budget, and all 57 deterministic behavior tests passed. The skin does not change the already certified data, search, Gmail, recipient-directory, or thread-opening architecture. A later short soak diagnostic was rejected because macOS Launch Services stalled the untouched baseline and candidate after repeated automated application launches; it is retained as environmental evidence and is not mixed into the release comparison.

## Post-feature regression certification

The comparison used 40 matched baseline/current pairs on the same Mac. Each pair ran the same production-optimized benchmark against the same deterministic 10,000-thread fixture. The value below is the median of each pair's p95 percentage change; negative values are improvements. The release gate is `delta <= +5.000%` for every metric, without rounding before the decision.

| Metric | Median paired p95 delta | Gate |
| --- | ---: | --- |
| Archive action | -0.009% | Pass |
| Background search index ready | -1.327% | Pass |
| Command-K input feedback | -0.037% | Pass |
| Command-K open state | -11.139% | Pass |
| Command-K results | +0.098% | Pass |
| HTML message normalization | -3.888% | Pass |
| Materialize 200 inbox rows | -0.148% | Pass |
| Keyboard navigation | +1.843% | Pass |
| Local search | +0.354% | Pass |
| Mark read or unread | +0.643% | Pass |
| Open cached message state | -2.585% | Pass |
| Rapid navigation, per step | +0.925% | Pass |
| Reply composer state | -55.640% | Pass |
| Reply typing update | +1.412% | Pass |
| SQLite FTS search | +0.665% | Pass |
| SQLite seed replacement | +0.640% | Pass |
| SQLite uncached thread load | -0.640% | Pass |
| SQLite warm mailbox load | +0.064% | Pass |
| Warm inbox model | +1.250% | Pass |

The historical baseline came from the canonical pre-feature source snapshot. Only identical benchmark fixture, probe, and harness changes were applied to both trees; product behavior remained historical in the baseline. Runs used foreground scheduling, counterbalanced execution order, and an absolute-budget validity check. Pairs affected by system contention were retained under `rejected/` for diagnosis but excluded from the comparison rather than counted as product regressions.

## Final launch confirmation

The launch probe waits for all 10,000 cached summaries, two main-queue UI commits, and a displayed key window before recording the first useful frame.

| Launch path | Current | Budget | Result |
| --- | ---: | ---: | --- |
| Cold first useful frame | 1,314.09 ms | Measured, no numeric release limit | Recorded |
| Warm first useful frame p75 | 436.20 ms | 500 ms | Pass |
| Warm first useful frame p95 | 452.73 ms | 1,000 ms | Pass |

## Final sustained-use confirmation

A final counterbalanced comparison ran three matched five-minute pairs: 15 minutes and 4,500 actions for the historical build, plus 15 minutes and 4,500 actions for the production build. Every pair used the same reset 10,000-thread fixture and the same instrumentation. The value below is the median paired percentage change; negative values are improvements.

| Sustained-use metric | Median paired change | Gate | Result |
| --- | ---: | ---: | --- |
| Action latency p75 | -32.584% | <= +5.000% | Pass |
| Action latency p95 | -11.433% | <= +5.000% | Pass |
| Main-queue delay p75 | -6.973% | <= +5.000% | Pass |
| Main-queue delay p95 | -17.717% | <= +5.000% | Pass |
| Main-run-loop CPU work p75 | -0.439% | <= +5.000% | Pass |
| Main-run-loop CPU work p95 | -7.085% | <= +5.000% | Pass |

Every accepted production run also passed the pre-existing absolute release ceilings:

| Production tail diagnostic | Worst accepted run | Budget | Result |
| --- | ---: | ---: | --- |
| Action latency p95 | 9.94 ms | 100 ms | Pass |
| Main-queue delay p95 | 8.14 ms | 16.667 ms | Pass |
| Main-run-loop CPU work max | 42.81 ms | 50 ms | Pass |
| Main-thread tasks over 50 ms | 0 | 0 | Pass |
| Resident-memory growth | -13,568 KB | <= +10,240 KB | Pass |

Percentile latency is the stable relative-regression measure. Single-run maxima and resident-memory endpoints are tail diagnostics, so they retain their pre-existing absolute release ceilings rather than a percentage gate. One production attempt encountered three isolated macOS stalls and was rejected because it exceeded the 50 ms tail ceiling; its evidence is preserved under `rejected/`, and the clean retry passed. Two historical runs missed a modern tail or memory ceiling, which is reported but does not invalidate their percentile latency samples. All three accepted production runs passed every ceiling.

## Test profile

- Build: Swift release, whole-module optimization, warnings treated as errors
- Host: Apple silicon, 8 logical processors, 8 GB memory
- OS: macOS 27.0 build 26A5421a
- Fixture: 10,000 threads and 29,352 messages
- Stress cases: 104 forty-message conversations, 189 HTML-heavy messages, 1,525 attachment threads, and 113 inline-image threads
- Mail states: inbox, archive, sent, drafts, updates, receipts, read, unread, and starred

The interaction certification uses 40 matched pairs. The sustained-use certification uses the median paired change across three counterbalanced five-minute pairs and reports the worst production tail across all three accepted runs.

## Original optimization cycle

| Flow | Budget | Baseline p95 | Final worst p95 | Result |
| --- | ---: | ---: | ---: | --- |
| Keyboard navigation | 100 ms | 12.18 ms | 0.53 ms | Pass |
| Open cached message state | 400 ms | 1.70 ms | 0.56 ms | Pass |
| Rapid navigation, per step | 100 ms | 14.39 ms | 0.21 ms | Pass |
| Archive action | 100 ms | 17.49 ms | 3.01 ms | Pass |
| Mark read or unread | 100 ms | 2.07 ms | 0.61 ms | Pass |
| Local inbox search | 400 ms | 1,114.09 ms | 10.89 ms | Pass |
| Command-K search results | 400 ms | 1,668.71 ms | 48.83 ms | Pass |
| Reply composer state | 100 ms | 0.004 ms | 0.002 ms | Pass |
| SQLite cached mailbox load | 1,000 ms | 456.57 ms | 15.86 ms | Pass |
| Materialize 200 inbox rows | Reference | 10.57 ms | 0.37 ms | Pass |

Local inbox search improved by roughly 99%, Command-K results by 97%, cached mailbox loading by 96%, keyboard navigation by 95%, and rapid navigation by 98%.

## Original launch comparison

The launch probe does not stop at an empty shell. It waits until all 10,000 expected cached thread summaries are present, lets SwiftUI commit the hierarchy across two main-queue turns, forces the key window to display, and then records the first useful frame.

| Launch path | Baseline | Final | Budget | Result |
| --- | ---: | ---: | ---: | --- |
| Cold first useful frame | 3,116.75 ms | 1,027.34 ms | Measured, no numeric release limit | Recorded |
| Warm first useful frame p75 | 3,198.94 ms | 480.42 ms | 500 ms | Pass |
| Warm first useful frame p95 | 3,480.95 ms | 641.72 ms | 1,000 ms | Pass |

## Original 15-minute triage run

The final production app completed a 900-second run with 4,500 alternating navigation, thread-open, thread-close, search, Command-K, archive-state, and reply-state actions.

| Measure | Final |
| --- | ---: |
| Action latency p75 / p95 / max | 2.67 / 8.08 / 11.36 ms |
| Main-queue dispatch delay p75 / p95 / max | 0.07 / 6.76 / 52.38 ms |
| Main-run-loop CPU work p75 / p95 / max | 0.04 / 8.62 / 36.84 ms |
| Main-thread tasks longer than 50 ms | 0 |
| Resident memory start / peak / end | 102,496 / 102,496 / 62,032 KB |

The action and run-loop budgets pass, and resident memory declined rather than degrading over the session. The first full instrumented 15-minute iteration had 11 main-thread tasks over 50 ms and a 100.89 ms maximum; the final run reduced that to zero tasks over 50 ms and a 36.84 ms maximum.

## Bottlenecks and changes

- Cache startup decoded full message bodies and HTML for every thread. SQLite now maintains compact summary rows for inbox launch and hydrates a full conversation only when opened. SQLite creation and migration also move off `MailStore` initialization onto the Gmail actor.
- Search repeatedly normalized and scanned the full mailbox on the main actor. An immutable normalized index now serves local search asynchronously with cancellation, while SQLite FTS returns IDs first and loads only needed summaries.
- Broad observable mutations caused unrelated SwiftUI surfaces to invalidate. The store now keeps mailbox arrays, ID sets, and offsets incrementally and publishes only the view state that changed.
- Search, mailbox changes, and keyboard movement rebuilt too many rows or forced scroll animations. Inbox rows now use stable visual slots, initially materialize six rows, append in small groups, and recenter only after meaningful navigation.
- The hidden conversation hierarchy, rich HTML renderer, and reply editor stayed alive behind the inbox. The thread surface is created on demand, content is staged across short frames, and editors and WebKit renderers use small prewarmed pools.
- Long bodies were normalized repeatedly while one-line rows were measured. Cached summaries store normalized previews, and fallback preview normalization is bounded to the first 512 characters.
- Triage and send actions update local state immediately. Gmail persistence happens in the background, with the previous thread or draft restored and an error surfaced if the remote operation fails.
- The Gmail correspondent directory is built off the main actor from every thread containing sent mail. Metadata starts are capped at two per second and quota responses use minute-scale backoff because the current Gmail limit is 6,000 units per minute per user and `threads.get` costs 40 units. Progress and failures remain visible in the Gmail sheet, and completed addresses are cached in SQLite. See [Google's Gmail API usage limits](https://developers.google.com/workspace/gmail/api/reference/quota).

## Rerun

From the project root:

```bash
./scripts/test.sh
./scripts/build-app.sh
./scripts/benchmark.sh release-check 3
./scripts/benchmark-launch.sh release-launch-check 5
./scripts/soak-test.sh 900 release-soak-check
MAIL_PERF_PAIR_MODE=serial ./scripts/run-paired-performance.sh \
  /path/to/baseline-binary \
  .build/performance-benchmark \
  /private/tmp/keyboard-mail-paired \
  20 10000 5
./scripts/run-paired-soak.sh \
  /path/to/baseline-app/Contents/MacOS/KeyboardFirstMail \
  Mail.app/Contents/MacOS/KeyboardFirstMail \
  /private/tmp/keyboard-mail-paired-soak \
  3 300 5
```

The final-source 40-pair certification JSON is preserved under `performance-results.noindex/final-source-regression-20260903/`. The final cold and 20-sample warm launch evidence is under `performance-results.noindex/final-source-launch-20/`; the final paired sustained-use evidence is under `performance-results.noindex/final-paired-soak-20260903/`. Generated seeded SQLite files are intentionally ignored by Git and excluded from Spotlight indexing.

For regression checks, alternate baseline and candidate batches on the same host, then compare the median paired p95 delta. Pairing controls for transient CPU, thermal, and filesystem variance without relaxing the 5% ceiling.

## Remaining limitations

- Cold launch is much faster but remains just over one second on this host; the explicit release budget applies to warm cached launch, which passes.
- These numbers cover the current Apple-silicon 8 GB Mac. A lower-end supported Intel Mac remains a useful external validation target.
- Gmail network latency is not counted as local interaction latency. The interface acknowledges safe actions optimistically and reconciles or rolls back after the API response; the correspondent refresh is an asynchronous maintenance job loaded from SQLite on later launches.
- The launch benchmark intentionally waits for the full 10,000-summary model. Real Gmail caches currently contain fewer threads, so the measured launch path is heavier than the present account.
