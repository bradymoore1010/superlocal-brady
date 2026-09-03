import AppKit
import Darwin
import Foundation

/// Measures how long work submitted from a dedicated 60 Hz source waits for
/// the main queue. Keeping only one pulse in flight makes a long sample map to
/// one actual main-thread stall instead of a flood of delayed callbacks.
private struct MainQueuePulseSample: Sendable {
    let completedNanoseconds: UInt64
    let delayMilliseconds: Double
}

private struct StressActionSample: Sendable {
    let completedNanoseconds: UInt64
    let name: String
    let durationMilliseconds: Double
}

private final class MainQueuePulseMonitor: @unchecked Sendable {
    private let sourceQueue = DispatchQueue(
        label: "com.keyboardfirstmail.performance-main-queue-pulse",
        qos: .userInteractive
    )
    private let lock = NSLock()
    private var source: DispatchSourceTimer?
    private var isPulseInFlight = false
    private var samples: [MainQueuePulseSample] = []

    func start(reservingCapacity expectedSampleCount: Int = 0) {
        let source = DispatchSource.makeTimerSource(queue: sourceQueue)
        source.schedule(
            deadline: .now() + .milliseconds(100),
            repeating: .milliseconds(16),
            leeway: .milliseconds(1)
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            lock.lock()
            guard !isPulseInFlight else {
                lock.unlock()
                return
            }
            isPulseInFlight = true
            lock.unlock()

            let submitted = DispatchTime.now().uptimeNanoseconds
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let completed = DispatchTime.now().uptimeNanoseconds
                let delay = Double(completed - submitted) / 1_000_000
                lock.lock()
                samples.append(MainQueuePulseSample(
                    completedNanoseconds: completed,
                    delayMilliseconds: delay
                ))
                isPulseInFlight = false
                lock.unlock()
            }
        }
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        samples.reserveCapacity(expectedSampleCount)
        self.source = source
        lock.unlock()
        source.resume()
    }

    func stop() -> [MainQueuePulseSample] {
        lock.lock()
        let source = self.source
        self.source = nil
        let result = samples
        lock.unlock()
        source?.cancel()
        return result
    }

    func resetSamples() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

@MainActor
private final class MainRunLoopWorkMonitor {
    struct Sample {
        let completedNanoseconds: UInt64
        let wallMilliseconds: Double
        let cpuMilliseconds: Double
    }

    private var observer: CFRunLoopObserver?
    private var cycleStartedNanoseconds: UInt64?
    private var cycleStartedCPUNanoseconds: UInt64?
    private var samples: [Sample] = []

    func start(reservingCapacity expectedSampleCount: Int = 0) {
        samples.removeAll(keepingCapacity: true)
        samples.reserveCapacity(expectedSampleCount)
        let activities = CFRunLoopActivity(
            rawValue: CFRunLoopActivity.afterWaiting.rawValue
                | CFRunLoopActivity.beforeWaiting.rawValue
        )
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            activities.rawValue,
            true,
            0
        ) { [weak self] _, activity in
            MainActor.assumeIsolated {
                self?.record(activity)
            }
        }
        self.observer = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    func stop() -> [Sample] {
        if let observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
        observer = nil
        cycleStartedNanoseconds = nil
        cycleStartedCPUNanoseconds = nil
        return samples
    }

    func resetSamples() {
        samples.removeAll(keepingCapacity: true)
    }

    private func record(_ activity: CFRunLoopActivity) {
        let now = DispatchTime.now().uptimeNanoseconds
        if activity.contains(.afterWaiting) {
            cycleStartedNanoseconds = now
            cycleStartedCPUNanoseconds = currentThreadCPUNanoseconds()
        }
        if activity.contains(.beforeWaiting),
           let cycleStartedNanoseconds,
           let cycleStartedCPUNanoseconds {
            let cpuNow = currentThreadCPUNanoseconds()
            samples.append(Sample(
                completedNanoseconds: now,
                wallMilliseconds: Double(now - cycleStartedNanoseconds) / 1_000_000,
                cpuMilliseconds: Double(cpuNow - cycleStartedCPUNanoseconds) / 1_000_000
            ))
            self.cycleStartedNanoseconds = nil
            self.cycleStartedCPUNanoseconds = nil
        }
    }

    private func currentThreadCPUNanoseconds() -> UInt64 {
        var time = timespec()
        guard clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time) == 0 else { return 0 }
        return UInt64(time.tv_sec) * 1_000_000_000 + UInt64(time.tv_nsec)
    }
}

/// Opt-in production instrumentation used by the checked-in launch and soak
/// benchmarks. It is completely dormant unless MAIL_PERF_OUTPUT is present.
@MainActor
enum PerformanceProbe {
    private static var launchStartedNanoseconds: UInt64?
    private static var didStart = false
    private static var actionTimer: Timer?
    private static var mainQueuePulseMonitor: MainQueuePulseMonitor?
    private static var mainRunLoopWorkMonitor: MainRunLoopWorkMonitor?
    private static var actionDurations: [Double] = []
    private static var stressActionSamples: [StressActionSample] = []
    private static var actionCount = 0
    private static var firstFrameMilliseconds = 0.0
    private static var phases: [String: Double] = [:]
    private static var activityToken: NSObjectProtocol?

    static var fixtureThreadCount: Int? {
        guard let raw = ProcessInfo.processInfo.environment["MAIL_PERF_FIXTURE_COUNT"],
              let value = Int(raw), value > 0 else { return nil }
        return value
    }

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["MAIL_PERF_OUTPUT"] != nil
    }

    static func beginLaunch() {
        guard isEnabled, launchStartedNanoseconds == nil else { return }
        launchStartedNanoseconds = DispatchTime.now().uptimeNanoseconds
        phases["launchBegan"] = 0
    }

    static func markPhase(_ name: String) {
        guard isEnabled, let launchStartedNanoseconds else { return }
        phases[name] = elapsedMilliseconds(
            from: launchStartedNanoseconds,
            to: DispatchTime.now().uptimeNanoseconds
        )
    }

    static func viewAppeared(store: MailStore) {
        guard isEnabled, !didStart, hasExpectedMailbox(store) else { return }
        didStart = true
        markPhase("targetMailboxObserved")

        // Let SwiftUI commit and AppKit display the initial hierarchy before
        // recording the first useful frame.
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                NSApp.keyWindow?.displayIfNeeded()
                let now = DispatchTime.now().uptimeNanoseconds
                firstFrameMilliseconds = elapsedMilliseconds(
                    from: launchStartedNanoseconds ?? now,
                    to: now
                )
                let stressSeconds = Double(
                    ProcessInfo.processInfo.environment["MAIL_PERF_STRESS_SECONDS"] ?? "0"
                ) ?? 0
                if stressSeconds > 0 {
                    prepareStress(store: store, duration: stressSeconds)
                } else {
                    finish(store: store, stressDuration: 0)
                }
            }
        }
    }

    private static func hasExpectedMailbox(_ store: MailStore) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment["MAIL_PERF_EXPECTED_THREAD_COUNT"],
              let expected = Int(raw), expected > 0 else { return true }
        return store.threads.count == expected
    }

    private static func prepareStress(store: MailStore, duration: TimeInterval) {
        // Activation can make AppKit synchronously prepare the window and text
        // system. Do that before the steady-state monitor starts so the soak
        // measures triage interactions rather than one-time app activation.
        NSApp.activate(ignoringOtherApps: true)
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Preparing and measuring interactive Mail responsiveness"
        )
        // The observers themselves cause macOS to lazily initialize run-loop
        // and dispatch diagnostics. Start them before the UI warm-up, then
        // discard those setup samples at the actual measurement boundary.
        let pulseMonitor = MainQueuePulseMonitor()
        pulseMonitor.start(
            reservingCapacity: Int(ceil((duration + 10) * 70))
        )
        mainQueuePulseMonitor = pulseMonitor
        let runLoopMonitor = MainRunLoopWorkMonitor()
        runLoopMonitor.start(
            reservingCapacity: Int(ceil((duration + 10) * 120))
        )
        mainRunLoopWorkMonitor = runLoopMonitor
        Task {
            // The soak is a steady-state triage test. Launch, index creation,
            // first message hydration, and first FTS access have their own
            // dedicated benchmarks and are warmed here before sampling.
            await store.prepareSearchIndexForBenchmark()

            store.openSelected()
            try? await Task.sleep(for: .milliseconds(350))
            store.closeThread()

            store.searchText = "project"
            try? await Task.sleep(for: .milliseconds(350))
            store.searchText = ""

            store.commandQuery = "project"
            try? await Task.sleep(for: .milliseconds(350))
            store.commandQuery = ""

            // Exercise each row state once. SwiftUI and AppKit lazily prepare
            // selected-row and message text layouts on their first transition;
            // the launch benchmarks cover that one-time cost, while the soak
            // is intended to certify sustained interaction performance.
            store.moveThreadSelection(1)
            try? await Task.sleep(for: .milliseconds(200))
            store.openSelected()
            try? await Task.sleep(for: .milliseconds(200))
            store.closeThread()
            store.toggleUnread()
            try? await Task.sleep(for: .milliseconds(200))
            store.toggleUnread()
            store.toggleStar()
            try? await Task.sleep(for: .milliseconds(200))
            store.toggleStar()
            store.replyDraft.append("x")
            store.replyDraft.removeAll(keepingCapacity: true)

            // Return from the warm-up task before sampling. SwiftUI may defer
            // graph/layout commits until the enclosing main-actor job ends;
            // scheduling the boundary on a later turn lets those commits drain.
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(700)) {
                warmStressPath(cycle: 0, store: store, duration: duration)
            }
        }
    }

    private static func warmStressPath(cycle: Int, store: MailStore, duration: TimeInterval) {
        // One cycle only warms one hydrated conversation. Exercise several
        // distinct cached threads so editor reuse, thread teardown, summary
        // replacement, and inbox restoration are all steady before the timed
        // soak. Every monitor is reset below, so none of this enters results.
        guard cycle < 72 else {
            // Let the final warm-up transaction and asynchronous cached search
            // finish before resetting the monitors for the sustained gate.
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(700)) {
                startStress(store: store, duration: duration)
            }
            return
        }
        performStressAction(cycle, store: store)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
            warmStressPath(cycle: cycle + 1, store: store, duration: duration)
        }
    }

    private static func startStress(store: MailStore, duration: TimeInterval) {
        markPhase("soakSamplingBegan")
        actionDurations.removeAll(keepingCapacity: true)
        stressActionSamples.removeAll(keepingCapacity: true)
        let expectedActionCount = Int(ceil(duration / 0.20)) + 16
        actionDurations.reserveCapacity(expectedActionCount)
        stressActionSamples.reserveCapacity(expectedActionCount)
        actionCount = 0
        mainQueuePulseMonitor?.resetSamples()
        mainRunLoopWorkMonitor?.resetSamples()

        var cycle = 0
        // Five actions per second is a deliberately fast but human-reachable
        // keyboard triage cadence. It produces 4,500 actions in a 15-minute run.
        let actions = Timer(timeInterval: 0.20, repeats: true) { _ in
            MainActor.assumeIsolated {
                let start = DispatchTime.now().uptimeNanoseconds
                performStressAction(cycle, store: store)
                let completed = DispatchTime.now().uptimeNanoseconds
                let duration = elapsedMilliseconds(
                    from: start,
                    to: completed
                )
                actionDurations.append(duration)
                stressActionSamples.append(StressActionSample(
                    completedNanoseconds: completed,
                    name: stressActionName(cycle),
                    durationMilliseconds: duration
                ))
                actionCount += 1
                cycle += 1
            }
        }
        actions.tolerance = 0.005
        RunLoop.main.add(actions, forMode: .common)
        actionTimer = actions

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            finish(store: store, stressDuration: duration)
        }
    }

    private static func performStressAction(_ cycle: Int, store: MailStore) {
        switch cycle % 12 {
        case 0, 1:
            store.moveThreadSelection(1)
        case 2:
            store.openSelected()
        case 3:
            store.closeThread()
        case 4:
            store.toggleUnread()
        case 5:
            store.toggleStar()
        case 6:
            store.searchText = "delta\(cycle % 24)"
        case 7:
            store.searchText = ""
        case 8:
            store.commandQuery = "project"
        case 9:
            store.commandQuery = ""
        case 10:
            store.replyDraft.append("x")
            if store.replyDraft.count > 80 { store.replyDraft.removeAll(keepingCapacity: true) }
        default:
            store.archiveCurrent()
        }
    }

    private static func stressActionName(_ cycle: Int) -> String {
        switch cycle % 12 {
        case 0, 1: "navigate"
        case 2: "open"
        case 3: "close"
        case 4: "toggleUnread"
        case 5: "toggleStar"
        case 6: "search"
        case 7: "clearSearch"
        case 8: "commandSearch"
        case 9: "clearCommand"
        case 10: "replyType"
        default: "archive"
        }
    }

    private static func finish(store: MailStore, stressDuration: TimeInterval) {
        actionTimer?.invalidate()
        actionTimer = nil
        let mainQueueSamples = mainQueuePulseMonitor?.stop() ?? []
        mainQueuePulseMonitor = nil
        let mainRunLoopWork = mainRunLoopWorkMonitor?.stop() ?? []
        mainRunLoopWorkMonitor = nil
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
        }

        let mainQueueDelays = mainQueueSamples.map(\.delayMilliseconds)
        let sortedMainQueueDelays = mainQueueDelays.sorted()
        let mainRunLoopWallWork = mainRunLoopWork.map(\.wallMilliseconds)
        let mainRunLoopCPUWork = mainRunLoopWork.map(\.cpuMilliseconds)
        let sortedMainRunLoopWallWork = mainRunLoopWallWork.sorted()
        let sortedMainRunLoopCPUWork = mainRunLoopCPUWork.sorted()
        let sortedActions = actionDurations.sorted()
        let delayedMainQueueSamples = mainQueueDelays.filter { $0 > 50 }.count
        let longMainThreadTasks = mainRunLoopCPUWork.filter { $0 > 50 }.count
        let missedFrameBudgets = mainQueueDelays.filter { $0 > (1_000.0 / 60.0) }.count
        let launchStart = launchStartedNanoseconds ?? 0
        let slowMainQueueSamples: [[String: Any]] = mainQueueSamples
            .filter { $0.delayMilliseconds > 40 }
            .map {
                [
                    "elapsedMilliseconds": elapsedMilliseconds(
                        from: launchStart,
                        to: $0.completedNanoseconds
                    ),
                    "delayMilliseconds": $0.delayMilliseconds
                ]
            }
        let stressActions: [[String: Any]] = stressActionSamples.map {
            [
                "elapsedMilliseconds": elapsedMilliseconds(
                    from: launchStart,
                    to: $0.completedNanoseconds
                ),
                "name": $0.name,
                "durationMilliseconds": $0.durationMilliseconds
            ]
        }
        let slowMainRunLoopSamples: [[String: Any]] = mainRunLoopWork
            .filter { $0.wallMilliseconds > 40 || $0.cpuMilliseconds > 40 }
            .map {
                [
                    "elapsedMilliseconds": elapsedMilliseconds(
                        from: launchStart,
                        to: $0.completedNanoseconds
                    ),
                    "wallMilliseconds": $0.wallMilliseconds,
                    "cpuMilliseconds": $0.cpuMilliseconds
                ]
            }
        let report: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "buildConfiguration": "production-release",
            "fixtureThreadCount": store.threads.count,
            "firstFrameMilliseconds": firstFrameMilliseconds,
            "stressDurationSeconds": stressDuration,
            "actionCount": actionCount,
            "actionP75Milliseconds": percentile(0.75, sortedActions),
            "actionP95Milliseconds": percentile(0.95, sortedActions),
            "actionMaximumMilliseconds": sortedActions.last ?? 0,
            "mainQueueSampleCount": mainQueueDelays.count,
            "mainQueueDelayP75Milliseconds": percentile(0.75, sortedMainQueueDelays),
            "mainQueueDelayP95Milliseconds": percentile(0.95, sortedMainQueueDelays),
            "mainQueueDelayMaximumMilliseconds": sortedMainQueueDelays.last ?? 0,
            "mainQueueDelaysOver50Milliseconds": delayedMainQueueSamples,
            "mainQueueDelaysOverFrameBudget": missedFrameBudgets,
            "mainRunLoopWorkSampleCount": mainRunLoopWork.count,
            "mainRunLoopWorkP75Milliseconds": percentile(0.75, sortedMainRunLoopCPUWork),
            "mainRunLoopWorkP95Milliseconds": percentile(0.95, sortedMainRunLoopCPUWork),
            "mainRunLoopWorkMaximumMilliseconds": sortedMainRunLoopCPUWork.last ?? 0,
            "mainRunLoopWallWorkP75Milliseconds": percentile(0.75, sortedMainRunLoopWallWork),
            "mainRunLoopWallWorkP95Milliseconds": percentile(0.95, sortedMainRunLoopWallWork),
            "mainRunLoopWallWorkMaximumMilliseconds": sortedMainRunLoopWallWork.last ?? 0,
            "mainThreadTasksOver50Milliseconds": longMainThreadTasks,
            "slowMainQueueSamples": slowMainQueueSamples,
            "slowMainRunLoopSamples": slowMainRunLoopSamples,
            "stressActions": stressActions,
            "phasesMilliseconds": phases
        ]

        if let path = ProcessInfo.processInfo.environment["MAIL_PERF_OUTPUT"],
           let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            let url = URL(fileURLWithPath: path)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: url, options: .atomic)
        }

        if ProcessInfo.processInfo.environment["MAIL_PERF_EXIT_AFTER_PROBE"] == "1" {
            NSApp.terminate(nil)
        }
    }

    private static func percentile(_ percentile: Double, _ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, max(0, Int(ceil(percentile * Double(sorted.count))) - 1))
        return sorted[index]
    }

    private static func elapsedMilliseconds(from start: UInt64, to end: UInt64) -> Double {
        Double(end - start) / 1_000_000
    }
}
