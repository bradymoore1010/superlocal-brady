import Foundation

@main
struct SeedPerformanceMailbox {
    static func main() async throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard let directoryIndex = arguments.firstIndex(of: "--directory"),
              arguments.indices.contains(directoryIndex + 1) else {
            throw SeedError.missingDirectory
        }
        let count: Int
        if let countIndex = arguments.firstIndex(of: "--threads"),
           arguments.indices.contains(countIndex + 1) {
            count = Int(arguments[countIndex + 1]) ?? PerformanceInboxFixture.defaultThreadCount
        } else {
            count = PerformanceInboxFixture.defaultThreadCount
        }

        let directory = URL(fileURLWithPath: arguments[directoryIndex + 1], isDirectory: true)
        let databaseURL = directory.appendingPathComponent("mail.sqlite3")
        let repository = try SQLiteMailRepository(databaseURL: databaseURL)
        let threads = PerformanceInboxFixture.make(threadCount: count)
        try await repository.replaceMailbox(
            threads: threads,
            accountEmail: "performance@example.com",
            historyID: "10000",
            syncedAt: Date(timeIntervalSince1970: 1_788_364_800)
        )
        print("Seeded \(threads.count) threads at \(databaseURL.path)")
    }

    private enum SeedError: Error {
        case missingDirectory
    }
}
