import Darwin
import Foundation

private struct MetricResult: Codable {
    let name: String
    let unit: String
    let samples: Int
    let p50: Double
    let p75: Double
    let p95: Double
    let maximum: Double
    let budgetP95: Double?
    let passesBudget: Bool?
}

private struct BenchmarkEnvironment: Codable {
    let label: String
    let batch: Int
    let generatedAt: String
    let osVersion: String
    let processorCount: Int
    let physicalMemoryBytes: UInt64
    let buildConfiguration: String
    let gitCommit: String
}

private struct BenchmarkReport: Codable {
    let environment: BenchmarkEnvironment
    let fixture: PerformanceInboxFixture.Summary
    let metrics: [MetricResult]
    let checksum: Int
}

private enum BenchmarkFailure: Error {
    case missingOutput
    case fixtureWasNotLoaded
    case summaryLoadedMessageBodies
    case fullThreadWasNotHydrated
    case derivedMailboxStateMismatch
}

@main
struct PerformanceBenchmark {
    private static var checksum = 0

    static func main() async throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard let outputIndex = arguments.firstIndex(of: "--output"),
              arguments.indices.contains(outputIndex + 1) else {
            throw BenchmarkFailure.missingOutput
        }
        let outputURL = URL(fileURLWithPath: arguments[outputIndex + 1])
        let label = argument("--label", in: arguments) ?? "unlabeled"
        let batch = Int(argument("--batch", in: arguments) ?? "1") ?? 1
        let count = Int(argument("--threads", in: arguments) ?? "10000") ?? 10_000

        let fixture = PerformanceInboxFixture.make(threadCount: count)
        let fixtureSummary = PerformanceInboxFixture.summary(of: fixture)
        let listFixture = fixture.map(\.listSummary)
        var metrics: [MetricResult] = []

        let store = await MainActor.run {
            MailStore(
                initialThreads: listFixture,
                bootstrapGmail: false,
                startSearchIndexing: false,
                enableCachedSearch: false
            )
        }

        metrics.append(await measureMainActor(
            name: "warm_inbox_model",
            iterations: 15,
            warmups: 2,
            budgetP95: 500
        ) {
            let candidate = MailStore(
                initialThreads: listFixture,
                bootstrapGmail: false,
                startSearchIndexing: false,
                enableCachedSearch: false
            )
            Self.checksum &+= candidate.visibleThreads.count
        })

        metrics.append(await measureAsync(
            name: "background_search_index_ready",
            iterations: 1,
            warmups: 0,
            budgetP95: nil
        ) {
            await store.prepareSearchIndexForBenchmark()
        })

        metrics.append(await measureMainActorBatched(
            name: "keyboard_navigation",
            iterations: 40,
            warmups: 3,
            operationsPerSample: 50,
            budgetP95: 100
        ) { _ in
            store.moveThreadSelection(1)
            Self.checksum &+= store.selectedThreadID?.count ?? 0
        })

        metrics.append(await measureMainActorBatched(
            name: "mouse_open_cached_message",
            iterations: 40,
            warmups: 3,
            operationsPerSample: 8,
            budgetP95: 100
        ) { iteration in
            let thread = listFixture[(iteration * 211) % listFixture.count]
            store.closeThread()
            store.open(thread)
            Self.checksum &+= store.openedThreadID?.count ?? 0
        })

        metrics.append(await measureMainActor(
            name: "rapid_navigation_per_step",
            iterations: 20,
            warmups: 2,
            budgetP95: 100
        ) {
            for _ in 0..<50 { store.moveThreadSelection(1) }
            Self.checksum &+= store.selectedThreadID?.count ?? 0
        }.divided(by: 50))

        metrics.append(await measureMainActor(
            name: "archive_action",
            iterations: 30,
            warmups: 2,
            budgetP95: 100
        ) { iteration in
            let thread = listFixture[5 + iteration]
            store.selectedThreadID = thread.id
            store.openedThreadID = nil
            store.archiveCurrent()
            Self.checksum &+= store.selectedThreadID?.count ?? 0
        })

        metrics.append(await measureMainActor(
            name: "mark_read_unread_action",
            iterations: 60,
            warmups: 4,
            budgetP95: 100
        ) { iteration in
            let thread = listFixture[(iteration * 37) % listFixture.count]
            store.selectedThreadID = thread.id
            store.openedThreadID = nil
            store.toggleUnread()
            Self.checksum &+= store.threads[(iteration * 37) % fixture.count].isUnread ? 1 : 0
        })

        metrics.append(await measureAsync(
            name: "local_search",
            iterations: 24,
            warmups: 2,
            budgetP95: 400
        ) { iteration in
            let queries = ["quarterly delta7", "from:sender42 project", "has:attachment forecast", "subject:security delta3"]
            await MainActor.run {
                store.searchText = queries[iteration % queries.count]
            }
            await store.awaitVisibleSearchForBenchmark()
            await MainActor.run {
                Self.checksum &+= store.visibleThreads.count
            }
        })

        metrics.append(await measureMainActorBatched(
            name: "command_k_input_feedback",
            iterations: 40,
            warmups: 3,
            operationsPerSample: 100,
            budgetP95: 100
        ) { iteration in
            store.commandQuery = iteration.isMultiple(of: 2) ? "project" : "forecast"
            Self.checksum &+= store.commandQuery.count
        })
        await store.awaitPaletteSearchForBenchmark()

        metrics.append(await measureAsync(
            name: "command_k_results",
            iterations: 24,
            warmups: 2,
            budgetP95: 400
        ) { iteration in
            let queries = ["project", "sender42", "forecast", "archive"]
            await MainActor.run {
                store.commandQuery = queries[iteration % queries.count]
            }
            await store.awaitPaletteSearchForBenchmark()
            await MainActor.run {
                Self.checksum &+= store.paletteResultCount
            }
        })

        metrics.append(await measureMainActorBatched(
            name: "command_k_open_state",
            iterations: 40,
            warmups: 3,
            operationsPerSample: 1_000,
            budgetP95: 100
        ) { _ in
            store.toggleCommandPalette()
            Self.checksum &+= store.isCommandPalettePresented ? 1 : 0
        })

        await MainActor.run {
            store.searchText = ""
            store.selectedMailbox = .inbox
            store.openedThreadID = listFixture[6].id
            store.selectedThreadID = listFixture[6].id
        }
        metrics.append(await measureMainActorBatched(
            name: "reply_composer_state",
            iterations: 40,
            warmups: 3,
            operationsPerSample: 100,
            budgetP95: 100
        ) { _ in
            store.requestReply()
            Self.checksum &+= store.replyFocusRequest
        })

        metrics.append(await measureMainActorBatched(
            name: "reply_typing_update",
            iterations: 40,
            warmups: 3,
            operationsPerSample: 1_000,
            budgetP95: 100
        ) { _ in
            store.replyDraft.append("x")
            if store.replyDraft.count > 240 {
                store.replyDraft.removeAll(keepingCapacity: true)
            }
            Self.checksum &+= store.replyDraft.count
        })

        metrics.append(measure(
            name: "inbox_row_materialization_200",
            iterations: 40,
            warmups: 3,
            budgetP95: nil
        ) {
            for thread in listFixture.prefix(200) {
                Self.checksum &+= thread.sender.count + thread.subject.count + thread.displayPreview.count
            }
        })

        if let html = fixture.lazy.flatMap(\.messages).first(where: { $0.htmlBody != nil })?.htmlBody {
            metrics.append(measure(
                name: "html_message_normalization",
                iterations: 40,
                warmups: 3,
                budgetP95: 400
            ) {
                Self.checksum &+= MailHTMLNormalizer.currentMessageHTML(html).count
            })
        }

        let databaseRoot = outputURL.deletingLastPathComponent().appendingPathComponent("database-\(batch)", isDirectory: true)
        try? FileManager.default.removeItem(at: databaseRoot)
        let databaseURL = databaseRoot.appendingPathComponent("mail.sqlite3")
        let repository = try SQLiteMailRepository(databaseURL: databaseURL)

        metrics.append(try await measureAsync(
            name: "sqlite_seed_replace",
            iterations: 1,
            warmups: 0,
            budgetP95: nil
        ) {
            try await repository.replaceMailbox(
                threads: fixture,
                accountEmail: "performance@example.com",
                historyID: "10000",
                syncedAt: Date(timeIntervalSince1970: 1_788_364_800)
            )
        })

        metrics.append(try await measureAsync(
            name: "sqlite_warm_mailbox_load",
            iterations: 7,
            warmups: 1,
            budgetP95: 1_000
        ) {
            guard let mailbox = try await repository.loadMailbox() else {
                throw BenchmarkFailure.fixtureWasNotLoaded
            }
            guard mailbox.threads.allSatisfy({ $0.messages.isEmpty }) else {
                throw BenchmarkFailure.summaryLoadedMessageBodies
            }
            Self.checksum &+= mailbox.threads.count
        })

        metrics.append(try await measureAsyncBatched(
            name: "sqlite_uncached_thread_load",
            iterations: 40,
            warmups: 2,
            operationsPerSample: 4,
            budgetP95: 400
        ) { iteration in
            let candidate = fixture[(iteration * 97) % fixture.count]
            guard let loaded = try await repository.cachedThread(id: candidate.id) else {
                throw BenchmarkFailure.fixtureWasNotLoaded
            }
            guard !loaded.messages.isEmpty else {
                throw BenchmarkFailure.fullThreadWasNotHydrated
            }
            Self.checksum &+= loaded.messages.count
        })

        metrics.append(try await measureAsync(
            name: "sqlite_fts_search",
            iterations: 30,
            warmups: 3,
            budgetP95: 400
        ) { iteration in
            let queries = ["quarterly", "sender42", "account plan", "delta7"]
            Self.checksum &+= try await repository.cachedThreads(
                matching: queries[iteration % queries.count],
                limit: 20
            ).count
        })

        let derivedStateIsConsistent = await MainActor.run {
            let expectedUnread = store.threads.filter { $0.folder == .inbox && $0.isUnread }.count
            let visibleIndexesAreValid = store.visibleThreads.enumerated().allSatisfy { index, thread in
                store.visibleThreadIndex(for: thread.id) == index
            }
            let expectedVisible = store.threads.filter {
                $0.folder == .inbox || $0.labels.contains(.inbox)
            }
            return store.unreadCount == expectedUnread
                && visibleIndexesAreValid
                && store.visibleThreads.map(\.id) == expectedVisible.map(\.id)
        }
        guard derivedStateIsConsistent else {
            throw BenchmarkFailure.derivedMailboxStateMismatch
        }

        let formatter = ISO8601DateFormatter()
        let environment = BenchmarkEnvironment(
            label: label,
            batch: batch,
            generatedAt: formatter.string(from: Date()),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            processorCount: ProcessInfo.processInfo.processorCount,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            buildConfiguration: "swiftc -O -whole-module-optimization",
            gitCommit: ProcessInfo.processInfo.environment["MAIL_PERF_GIT_COMMIT"] ?? "unknown"
        )
        let report = BenchmarkReport(
            environment: environment,
            fixture: fixtureSummary,
            metrics: metrics,
            checksum: checksum
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
        print("Wrote \(outputURL.path)")
        for metric in metrics {
            let budget = metric.budgetP95.map { " budget=\(format($0)) \(metric.passesBudget == true ? "PASS" : "FAIL")" } ?? ""
            print("\(metric.name): p75=\(format(metric.p75))ms p95=\(format(metric.p95))ms max=\(format(metric.maximum))ms\(budget)")
        }
        if metrics.contains(where: { $0.passesBudget == false }) {
            fputs("One or more absolute performance budgets failed.\n", stderr)
            exit(2)
        }
    }

    private static func argument(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func measure(
        name: String,
        iterations: Int,
        warmups: Int,
        budgetP95: Double?,
        operation: () throws -> Void
    ) rethrows -> MetricResult {
        for _ in 0..<warmups { try operation() }
        var values: [Double] = []
        values.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            try operation()
            values.append(milliseconds(since: start))
        }
        return result(name: name, values: values, budgetP95: budgetP95)
    }

    private static func measureMainActor(
        name: String,
        iterations: Int,
        warmups: Int,
        budgetP95: Double?,
        operation: @MainActor @escaping () -> Void
    ) async -> MetricResult {
        await MainActor.run {
            measure(name: name, iterations: iterations, warmups: warmups, budgetP95: budgetP95, operation: operation)
        }
    }

    private static func measureMainActorBatched(
        name: String,
        iterations: Int,
        warmups: Int,
        operationsPerSample: Int,
        budgetP95: Double?,
        operation: @MainActor @escaping (Int) -> Void
    ) async -> MetricResult {
        await MainActor.run {
            var operationIndex = 0
            for _ in 0..<warmups {
                for _ in 0..<operationsPerSample {
                    operation(operationIndex)
                    operationIndex += 1
                }
            }
            var values: [Double] = []
            values.reserveCapacity(iterations)
            for _ in 0..<iterations {
                let start = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<operationsPerSample {
                    operation(operationIndex)
                    operationIndex += 1
                }
                values.append(milliseconds(since: start))
            }
            return result(name: name, values: values, budgetP95: budgetP95)
                .divided(by: Double(operationsPerSample))
        }
    }

    private static func measureMainActor(
        name: String,
        iterations: Int,
        warmups: Int,
        budgetP95: Double?,
        operation: @MainActor @escaping (Int) -> Void
    ) async -> MetricResult {
        await MainActor.run {
            for iteration in 0..<warmups { operation(iteration) }
            var values: [Double] = []
            values.reserveCapacity(iterations)
            for iteration in 0..<iterations {
                let start = DispatchTime.now().uptimeNanoseconds
                operation(iteration)
                values.append(milliseconds(since: start))
            }
            return result(name: name, values: values, budgetP95: budgetP95)
        }
    }

    private static func measureAsync(
        name: String,
        iterations: Int,
        warmups: Int,
        budgetP95: Double?,
        operation: (Int) async throws -> Void
    ) async rethrows -> MetricResult {
        for iteration in 0..<warmups { try await operation(iteration) }
        var values: [Double] = []
        values.reserveCapacity(iterations)
        for iteration in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            try await operation(iteration)
            values.append(milliseconds(since: start))
        }
        return result(name: name, values: values, budgetP95: budgetP95)
    }

    private static func measureAsyncBatched(
        name: String,
        iterations: Int,
        warmups: Int,
        operationsPerSample: Int,
        budgetP95: Double?,
        operation: (Int) async throws -> Void
    ) async rethrows -> MetricResult {
        var operationIndex = 0
        for _ in 0..<warmups {
            for _ in 0..<operationsPerSample {
                try await operation(operationIndex)
                operationIndex += 1
            }
        }
        var values: [Double] = []
        values.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<operationsPerSample {
                try await operation(operationIndex)
                operationIndex += 1
            }
            values.append(milliseconds(since: start))
        }
        return result(name: name, values: values, budgetP95: budgetP95)
            .divided(by: Double(operationsPerSample))
    }

    private static func measureAsync(
        name: String,
        iterations: Int,
        warmups: Int,
        budgetP95: Double?,
        operation: () async throws -> Void
    ) async rethrows -> MetricResult {
        try await measureAsync(
            name: name,
            iterations: iterations,
            warmups: warmups,
            budgetP95: budgetP95
        ) { _ in try await operation() }
    }

    private static func milliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private static func result(name: String, values: [Double], budgetP95: Double?) -> MetricResult {
        let sorted = values.sorted()
        let p95 = percentile(0.95, sorted)
        return MetricResult(
            name: name,
            unit: "milliseconds",
            samples: sorted.count,
            p50: percentile(0.50, sorted),
            p75: percentile(0.75, sorted),
            p95: p95,
            maximum: sorted.last ?? 0,
            budgetP95: budgetP95,
            passesBudget: budgetP95.map { p95 <= $0 }
        )
    }

    private static func percentile(_ percentile: Double, _ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, max(0, Int(ceil(percentile * Double(sorted.count))) - 1))
        return sorted[index]
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private extension MetricResult {
    func divided(by divisor: Double) -> MetricResult {
        MetricResult(
            name: name,
            unit: unit,
            samples: samples,
            p50: p50 / divisor,
            p75: p75 / divisor,
            p95: p95 / divisor,
            maximum: maximum / divisor,
            budgetP95: budgetP95,
            passesBudget: budgetP95.map { p95 / divisor <= $0 }
        )
    }
}
