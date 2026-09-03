import AppKit
import Foundation
import Observation
import UserNotifications

private enum UndoableMailAction {
    case archive(previousThread: MailThread)
    case reply(
        previousThread: MailThread,
        draft: String,
        attachments: [DraftAttachment],
        inlineImages: [InlineDraftImage]
    )
    case compose(
        optimisticThreadID: String,
        to: String,
        subject: String,
        draft: String,
        attachments: [DraftAttachment],
        inlineImages: [InlineDraftImage]
    )
}

private struct PendingUndoableMailAction {
    let id: UUID
    let window: MailUndoWindow
    let action: UndoableMailAction
}

@MainActor
@Observable
final class MailStore {
    private(set) var threads: [MailThread] = MailThread.samples
    private(set) var visibleThreads: [MailThread] = MailThread.samples
    private(set) var paletteMailResults: [MailThread] = []
    private(set) var unreadCount = MailThread.samples.filter { $0.folder == .inbox && $0.isUnread }.count
    var selectedMailbox: Mailbox = .inbox {
        didSet {
            guard selectedMailbox != oldValue else { return }
            rebuildCurrentMailboxThreads()
            refreshVisibleThreads()
        }
    }
    var selectedThreadID: String? = "security-sign-in"
    var openedThreadID: String? = "security-sign-in"

    var isSearchPresented = false
    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            refreshVisibleThreads()
        }
    }
    var searchFocusRequest = 0

    var isCommandPalettePresented = false
    var commandPaletteMode: CommandPaletteMode = .commands
    var commandQuery = "" {
        didSet {
            guard commandQuery != oldValue else { return }
            refreshPaletteMailResults()
        }
    }
    var selectedCommandIndex = 0

    var replyDraft = ""
    var replyFocusRequest = 0
    // Opening/closing a thread and requesting focus already publish the state
    // changes that redraw ThreadView. Keeping these companion values out of
    // Observation avoids a second broad invalidation on the hot open path.
    @ObservationIgnored private(set) var replyFocusThreadID: String?
    @ObservationIgnored private(set) var isReplyComposerPresented = false
    var replyAttachments: [DraftAttachment] = []
    var replyInlineImages: [InlineDraftImage] = []
    var replyFormattingRequest: MailEditorRequest?
    var replyInlineImageRequest: MailInlineImageRequest?
    var isComposerOverlayPresented = false {
        didSet {
            if oldValue, !isComposerOverlayPresented {
                lastComposerOverlayDismissal = Date()
            }
        }
    }

    var isComposePresented = false
    var composeTo = "" {
        didSet {
            guard composeTo != oldValue else { return }
            if composeTo != suppressedRecipientSuggestionsForValue {
                suppressedRecipientSuggestionsForValue = nil
            }
            selectedComposeRecipientSuggestionIndex = 0
        }
    }
    var selectedComposeRecipientSuggestionIndex = 0
    var composeSubject = ""
    var composeBody = ""
    var composeAttachments: [DraftAttachment] = []
    var composeInlineImages: [InlineDraftImage] = []
    var composeFormattingRequest: MailEditorRequest?
    var composeInlineImageRequest: MailInlineImageRequest?

    var toastMessage: String?
    var pendingUnsubscribe: PendingUnsubscribe?
    var pendingSenderBlock: PendingSenderBlock?
    private(set) var reminderDates: [String: Date] = [:]

    var gmailConnectionState: GmailConnectionState = .disconnected
    var gmailHasConfiguration = false
    var isGmailSetupPresented = false
    private(set) var gmailRecipientDirectoryStatus: String?

    private var pendingGoKey = false
    private var pendingGoDate = Date.distantPast
    private var lastComposerOverlayDismissal = Date.distantPast
    private var loadingAttachmentMetadata: Set<UUID> = []
    private let gmailIntegration = GmailIntegration()
    private var gmailSyncTask: Task<Void, Never>?
    private var gmailSearchTask: Task<Void, Never>?
    @ObservationIgnored private var gmailRecipientDirectoryTask: Task<Void, Never>?
    private var hydratingThreadIDs: Set<String> = []
    private var loadingCachedThreadIDs: Set<String> = []
    private(set) var threadBodyLoadErrors: [String: String] = [:]
    private var hydratedThreadCache: [String: MailThread] = [:]
    private var hydratedThreadCacheOrder: [String] = []
    private var reminderWakeTask: Task<Void, Never>?
    private var threadOffsetsByID: [String: Int] = [:]
    private var currentMailboxThreads: [MailThread] = []
    private var currentMailboxThreadOffsetsByID: [String: Int] = [:]
    private var currentMailboxThreadIDs: Set<String> = []
    private var visibleThreadOffsetsByID: [String: Int] = [:]
    private var searchIndex = MailSearchEngine.Index()
    private var searchIndexTask: Task<Void, Never>?
    private var visibleSearchTask: Task<Void, Never>?
    private var paletteSearchTask: Task<Void, Never>?
    private var searchIndexGeneration = 0
    private var visibleSearchGeneration = 0
    private var paletteSearchGeneration = 0
    private var isSearchIndexReady = false
    private var pendingSearchMetadata: [String: MailThread] = [:]
    private var pendingSearchReplacements: [String: MailThread] = [:]
    private var pendingSearchRemovals: Set<String> = []
    private var cachedSearchEnabled = true
    private var recipientAutocomplete = RecipientAutocompleteIndex()
    @ObservationIgnored private var gmailRecipientDirectory: [RecipientSuggestion] = []
    @ObservationIgnored private var gmailRecipientDirectorySyncedAt: Date?
    @ObservationIgnored private var blockedSenderAddresses: Set<String> = []
    @ObservationIgnored private var pendingUndoActions: [PendingUndoableMailAction] = []
    @ObservationIgnored private var pendingUndoTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var toastClearTask: Task<Void, Never>?
    @ObservationIgnored private var archivingBlockedThreadIDs: Set<String> = []
    private var suppressedRecipientSuggestionsForValue: String?
    private var draftCount = MailThread.samples.filter { $0.folder == .drafts || $0.labels.contains(.drafts) }.count

    init(
        initialThreads: [MailThread] = MailThread.samples,
        bootstrapGmail: Bool = true,
        startSearchIndexing: Bool = true,
        enableCachedSearch: Bool = true
    ) {
        cachedSearchEnabled = enableCachedSearch
        blockedSenderAddresses = Self.loadBlockedSenderAddresses()
        threads = initialThreads.sorted { $0.date > $1.date }
        let initialSelection = threads.first(where: { $0.id == "security-sign-in" })?.id
            ?? threads.first?.id
        selectedThreadID = initialSelection
        // Production launches into the inbox. Avoid constructing an off-screen
        // message thread and native editor while the Gmail cache is loading.
        openedThreadID = bootstrapGmail ? nil : initialSelection
        if !bootstrapGmail,
           let initialSelection,
           let initialThread = threads.first(where: { $0.id == initialSelection }) {
            isReplyComposerPresented = initialThread.shouldOpenReplyComposerByDefault
        }
        reminderDates = Self.loadReminderDates()
        rebuildThreadCaches()
        clearDueReminders()
        if startSearchIndexing {
            scheduleSearchIndexRebuild()
        }
        if bootstrapGmail {
            Task { [weak self] in
                await self?.bootstrapGmail()
            }
        }
    }

    var windowTitle: String {
        if let openedThread { return openedThread.subject }
        return selectedMailbox.rawValue
    }

    var openedThread: MailThread? {
        guard let openedThreadID else { return nil }
        return thread(withID: openedThreadID)
    }

    var commands: [MailCommand] {
        var values = [
            MailCommand(action: .compose, title: "Compose message", subtitle: "Start a new email", icon: "plus", shortcut: "C", keywords: ["new", "write", "email"]),
            MailCommand(action: .search, title: "Search mail", subtitle: "Find sender, subject, text, or filters", icon: "magnifyingglass", shortcut: "/", keywords: ["find", "lookup", "from", "subject"]),
            MailCommand(action: .scheduleSend, title: "Schedule send", subtitle: "Choose a suggested or custom send time", icon: "clock", shortcut: "", keywords: ["later", "delay", "send", "time"]),
            MailCommand(action: .signatures, title: "Set signatures", subtitle: "Create and format signatures with hyperlinks", icon: "signature", shortcut: "S", keywords: ["signature", "footer", "link", "format"]),
            MailCommand(action: .archiveCurrent, title: "Archive current", subtitle: openedThread == nil ? "Archive the selected conversation" : "Archive this conversation", icon: "arrow.down", shortcut: "E", keywords: ["remove", "done", "inbox"]),
            MailCommand(action: .reply, title: "Reply", subtitle: "Focus the reply field", icon: "arrowshape.turn.up.left", shortcut: "R", keywords: ["respond", "answer"]),
            MailCommand(action: .toggleStar, title: "Toggle star", subtitle: "Star or unstar the current conversation", icon: "star", shortcut: "S", keywords: ["favorite", "important"]),
            MailCommand(action: .toggleUnread, title: "Mark read or unread", subtitle: "Toggle the current conversation state", icon: "envelope.badge", shortcut: "U", keywords: ["read", "unread"]),
            MailCommand(action: .inbox, title: "Go to Inbox", subtitle: nil, icon: "tray", shortcut: "G then I", keywords: ["navigate", "mailbox"]),
            MailCommand(action: .starred, title: "Go to Starred", subtitle: nil, icon: "star", shortcut: "G then S", keywords: ["navigate", "favorites"]),
            MailCommand(action: .sent, title: "Go to Sent", subtitle: nil, icon: "paperplane", shortcut: "G then T", keywords: ["navigate", "outgoing"]),
            MailCommand(action: .drafts, title: "Go to Drafts", subtitle: nil, icon: "doc", shortcut: "G then D", keywords: ["navigate", "writing"]),
            MailCommand(action: .archiveMailbox, title: "Go to Archive", subtitle: nil, icon: "archivebox", shortcut: "G then A", keywords: ["navigate", "saved"])
        ]

        if commandTargetThread != nil {
            values.insert(
                MailCommand(
                    action: .remind,
                    title: "Remind me…",
                    subtitle: "Hide this conversation until a chosen time",
                    icon: "bell",
                    shortcut: "",
                    keywords: ["reminder", "snooze", "later", "follow up"]
                ),
                at: min(5, values.count)
            )
        }
        if let target = commandTargetThread,
           target.unsubscribeMethod != nil || isLiveGmailThread(target) {
            values.insert(
                MailCommand(
                    action: .unsubscribe,
                    title: "Unsubscribe",
                    subtitle: "Stop future mailing-list messages",
                    icon: "xmark.circle",
                    shortcut: "",
                    keywords: ["newsletter", "mailing list", "stop email"]
                ),
                at: min(6, values.count)
            )
        }
        if let target = commandTargetThread {
            let address = SenderBlockPolicy.normalizedAddress(target.email)
            if !address.isEmpty, !blockedSenderAddresses.contains(address) {
                values.insert(
                    MailCommand(
                        action: .blockSender,
                        title: "Block sender",
                        subtitle: "Keep future messages from (target.sender) out of the inbox",
                        icon: "hand.raised",
                        shortcut: "",
                        keywords: ["sender", "spam", "mute", "stop email"]
                    ),
                    at: min(7, values.count)
                )
            }
        }
        return values
    }

    var filteredCommands: [MailCommand] {
        let query = MailSearchEngine.normalize(commandQuery.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return commands }
        let terms = query.split(separator: " ").map(String.init)

        return commands.compactMap { command -> (MailCommand, Int)? in
            let title = MailSearchEngine.normalize(command.title)
            let subtitle = MailSearchEngine.normalize(command.subtitle ?? "")
            let keywords = MailSearchEngine.normalize(command.keywords.joined(separator: " "))
            guard terms.allSatisfy({ title.contains($0) || subtitle.contains($0) || keywords.contains($0) }) else { return nil }

            var score = 0
            for term in terms {
                if title.hasPrefix(term) { score += 80 }
                else if title.split(separator: " ").contains(where: { $0.hasPrefix(term) }) { score += 55 }
                else if title.contains(term) { score += 35 }
                else if keywords.contains(term) { score += 18 }
                else { score += 8 }
            }
            return (command, score)
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }

    var paletteResultCount: Int {
        filteredCommands.count + paletteMailResults.count
    }

    var composeRecipientSuggestions: [RecipientSuggestion] {
        guard composeTo != suppressedRecipientSuggestionsForValue else { return [] }
        return recipientAutocomplete.suggestions(matching: composeTo)
    }

    func count(for mailbox: Mailbox) -> Int? {
        switch mailbox {
        case .inbox: unreadCount
        case .drafts: draftCount
        default: nil
        }
    }

    func presentGmailSetup() {
        closeCommandPalette()
        isComposePresented = false
        isGmailSetupPresented = true
    }

    func closeGmailSetup() {
        switch gmailConnectionState {
        case .connecting, .syncing:
            return
        default:
            isGmailSetupPresented = false
        }
    }

    func openGoogleCloudSetup() {
        guard let url = URL(string: "https://console.cloud.google.com/apis/credentials") else { return }
        NSWorkspace.shared.open(url)
    }

    func chooseGmailConfiguration() {
        GmailCredentialPickerController.shared.present { [weak self] url in
            guard let self, let url else { return }
            Task { @MainActor in
                do {
                    try await self.gmailIntegration.importConfiguration(from: url)
                    self.gmailHasConfiguration = true
                    self.gmailConnectionState = .readyToConnect
                } catch {
                    self.gmailConnectionState = .failed(message: Self.userFacingMessage(for: error))
                }
            }
        }
    }

    func connectGmail() {
        guard gmailHasConfiguration else {
            gmailConnectionState = .disconnected
            presentGmailSetup()
            return
        }
        guard gmailSyncTask == nil else { return }
        isGmailSetupPresented = true
        gmailConnectionState = .connecting
        gmailSyncTask = Task { [weak self] in
            guard let self else { return }
            defer { gmailSyncTask = nil }
            do {
                let snapshot = try await gmailIntegration.connect { [weak self] completed, total in
                    await self?.updateGmailSyncProgress(completed: completed, total: total)
                }
                apply(snapshot)
                gmailConnectionState = .connected(email: snapshot.accountEmail, syncedAt: snapshot.syncedAt)
                toast("Gmail connected")
                refreshGmailRecipientDirectoryIfNeeded(force: true)
            } catch {
                gmailConnectionState = .failed(message: Self.userFacingMessage(for: error))
            }
        }
    }

    func syncGmail() {
        startGmailSync(
            showSetupOnFailure: true,
            forceRecipientDirectoryRefresh: true
        )
    }

    func searchGmailIfNeeded(_ rawQuery: String) {
        gmailSearchTask?.cancel()
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard gmailConnectionState.isConnected, query.count >= 2 else { return }

        gmailSearchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(320))
                guard !Task.isCancelled, let self else { return }
                let results = try await gmailIntegration.searchGmail(query)
                guard !Task.isCancelled else { return }
                var byID = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0) })
                for thread in results { byID[thread.id] = thread }
                replaceAllThreads(Array(byID.values))
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    func selectMailbox(_ mailbox: Mailbox) {
        selectedMailbox = mailbox
        openedThreadID = nil
        clearReplyPresentation()
        isComposerOverlayPresented = false
        searchText = ""
        isSearchPresented = false
        selectedThreadID = visibleThreads.first?.id
    }

    func open(_ thread: MailThread) {
        var openingThread = thread
        if thread.messages.isEmpty,
           let hydrated = hydratedThreadForOpening(threadID: thread.id) {
            replaceThread(hydrated, replacingID: thread.id)
            openingThread = hydrated
        }

        selectedThreadID = openingThread.id
        openedThreadID = openingThread.id
        configureReplyPresentation(for: openingThread)
        isComposerOverlayPresented = false
        setUnread(false, threadID: openingThread.id)
        if openingThread.messages.isEmpty {
            hydrateCachedThreadIfNeeded(threadID: openingThread.id)
        } else {
            hydrateInlineContentIfNeeded(openingThread)
        }
    }

    func closeThread() {
        openedThreadID = nil
        clearReplyPresentation()
        isComposerOverlayPresented = false
    }

    func requestSearch() {
        openedThreadID = nil
        clearReplyPresentation()
        isCommandPalettePresented = false
        isSearchPresented = true
        searchFocusRequest += 1
    }

    func dismissSearch() {
        searchText = ""
        isSearchPresented = false
    }

    func presentCommandPalette() {
        guard !isCommandPalettePresented else { return }
        isCommandPalettePresented = true
        if commandPaletteMode != .commands { commandPaletteMode = .commands }
        if !commandQuery.isEmpty { commandQuery = "" }
        if selectedCommandIndex != 0 { selectedCommandIndex = 0 }
    }

    func toggleCommandPalette() {
        if isCommandPalettePresented {
            // The palette is hidden immediately. Reset its transient mode only
            // when it is opened again, keeping the close hot path to one state
            // mutation while preserving the same next-open behavior.
            isCommandPalettePresented = false
        } else {
            presentCommandPalette()
        }
    }

    func closeCommandPalette() {
        isCommandPalettePresented = false
        if commandPaletteMode != .commands { commandPaletteMode = .commands }
        if !commandQuery.isEmpty { commandQuery = "" }
        if selectedCommandIndex != 0 { selectedCommandIndex = 0 }
    }

    func moveCommandSelection(_ delta: Int) {
        let count = paletteResultCount
        guard count > 0 else { selectedCommandIndex = 0; return }
        selectedCommandIndex = (selectedCommandIndex + delta + count) % count
    }

    func clampCommandSelection() {
        selectedCommandIndex = min(selectedCommandIndex, max(paletteResultCount - 1, 0))
    }

    func moveComposeRecipientSelection(_ delta: Int) {
        let suggestions = composeRecipientSuggestions
        guard !suggestions.isEmpty else {
            selectedComposeRecipientSuggestionIndex = 0
            return
        }
        selectedComposeRecipientSuggestionIndex = (
            selectedComposeRecipientSuggestionIndex + delta + suggestions.count
        ) % suggestions.count
    }

    @discardableResult
    func acceptComposeRecipientSuggestion(_ suggestion: RecipientSuggestion? = nil) -> Bool {
        let suggestions = composeRecipientSuggestions
        let selectedSuggestion = suggestions.indices.contains(selectedComposeRecipientSuggestionIndex)
            ? suggestions[selectedComposeRecipientSuggestionIndex]
            : nil
        let chosen = suggestion ?? selectedSuggestion
        guard let chosen else { return false }
        let replacement = RecipientAutocompleteIndex.replacingActiveRecipient(
            in: composeTo,
            with: chosen
        )
        composeTo = replacement
        suppressedRecipientSuggestionsForValue = replacement
        selectedComposeRecipientSuggestionIndex = 0
        return true
    }

    func executeSelectedCommand() {
        let commands = filteredCommands
        if commands.indices.contains(selectedCommandIndex) {
            perform(commands[selectedCommandIndex].action)
            return
        }

        let mailIndex = selectedCommandIndex - commands.count
        let mail = paletteMailResults
        guard mail.indices.contains(mailIndex) else { return }
        openFromCommandPalette(mail[mailIndex])
    }

    func openFromCommandPalette(_ thread: MailThread) {
        closeCommandPalette()
        selectedMailbox = thread.folder
        selectedThreadID = thread.id
        open(thread)
    }

    func perform(_ action: CommandAction) {
        if action == .scheduleSend {
            commandPaletteMode = .scheduleSend
            return
        }
        if action == .signatures {
            commandPaletteMode = .signatures
            return
        }
        if action == .remind {
            commandPaletteMode = .reminder
            return
        }

        closeCommandPalette()
        switch action {
        case .compose:
            presentCompose()
        case .search:
            requestSearch()
        case .scheduleSend, .signatures, .remind:
            break
        case .inbox:
            selectMailbox(.inbox)
        case .starred:
            selectMailbox(.starred)
        case .sent:
            selectMailbox(.sent)
        case .drafts:
            selectMailbox(.drafts)
        case .archiveMailbox:
            selectMailbox(.archive)
        case .archiveCurrent:
            archiveCurrent()
        case .unsubscribe:
            requestUnsubscribe()
        case .blockSender:
            requestBlockSender()
        case .reply:
            requestReply()
        case .toggleStar:
            toggleStar()
        case .toggleUnread:
            toggleUnread()
        }
    }

    func moveThreadSelection(_ delta: Int) {
        let list = visibleThreads
        guard !list.isEmpty else { selectedThreadID = nil; return }
        let current = selectedThreadID.flatMap { visibleThreadOffsetsByID[$0] } ?? (delta > 0 ? -1 : 0)
        let next = min(max(current + delta, 0), list.count - 1)
        selectedThreadID = list[next].id

        if openedThreadID != nil {
            open(list[next])
        } else {
            hydrateCachedThreadIfNeeded(threadID: list[next].id)
        }
    }

    func visibleThreadIndex(for id: String) -> Int? {
        visibleThreadOffsetsByID[id]
    }

    func openSelected() {
        guard let id = selectedThreadID, let thread = thread(withID: id) else { return }
        open(thread)
    }

    func archiveCurrent() {
        guard let id = openedThreadID ?? selectedThreadID,
              let previousThread = thread(withID: id) else { return }
        guard previousThread.folder != .archive else { return }
        let wasReading = openedThreadID == id
        let nextThreadID = MailTriagePolicy.nextThreadID(
            afterRemoving: id,
            from: visibleThreads
        )
        mutateThread(withID: id) { thread in
            thread.folder = .archive
            thread.labels.remove(.inbox)
            thread.labels.insert(.archive)
            thread.gmailLabelIDs.remove("INBOX")
        }

        if wasReading {
            if let nextThreadID,
               let nextThread = thread(withID: nextThreadID),
               visibleThreadOffsetsByID[nextThreadID] != nil {
                open(nextThread)
            } else {
                closeThread()
                selectedThreadID = visibleThreads.first?.id
            }
        } else {
            selectedThreadID = nextThreadID.flatMap { visibleThreadOffsetsByID[$0] != nil ? $0 : nil }
                ?? visibleThreads.first?.id
        }

        let undoID = registerUndo(
            .archive(previousThread: previousThread),
            message: "Archived"
        )
        pendingUndoTasks[undoID] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(MailUndoWindow.duration))
            } catch {
                return
            }
            guard let self, finalizePendingUndo(id: undoID) else { return }
            guard isLiveGmailThread(previousThread) else { return }
            do {
                try await gmailIntegration.archive(threadID: id)
                if let updatedThread = thread(withID: id) {
                    try await gmailIntegration.persistLocalThreadState(updatedThread)
                }
            } catch {
                replaceThread(previousThread)
                toast("Archive failed: \(Self.userFacingMessage(for: error))")
            }
        }
    }

    func toggleStar() {
        guard let id = openedThreadID ?? selectedThreadID,
              let previousThread = thread(withID: id) else { return }
        mutateThread(withID: id) { thread in
            thread.isStarred.toggle()
            if thread.isStarred { thread.gmailLabelIDs.insert("STARRED") }
            else { thread.gmailLabelIDs.remove("STARRED") }
        }
        guard let updatedThread = thread(withID: id) else { return }
        toast(updatedThread.isStarred ? "Starred" : "Unstarred")

        guard isLiveGmailThread(previousThread) else { return }
        let newValue = updatedThread.isStarred
        Task { [weak self] in
            guard let self else { return }
            do {
                try await gmailIntegration.setStarred(newValue, threadID: id)
                if let updatedThread = thread(withID: id) {
                    try await gmailIntegration.persistLocalThreadState(updatedThread)
                }
            } catch {
                replaceThread(previousThread)
                toast("Star update failed: \(Self.userFacingMessage(for: error))")
            }
        }
    }

    func toggleUnread() {
        guard let id = openedThreadID ?? selectedThreadID,
              let previousThread = thread(withID: id) else { return }
        mutateThread(withID: id) { thread in
            thread.isUnread.toggle()
            if thread.isUnread { thread.gmailLabelIDs.insert("UNREAD") }
            else { thread.gmailLabelIDs.remove("UNREAD") }
        }
        guard let updatedThread = thread(withID: id) else { return }
        toast(updatedThread.isUnread ? "Marked unread" : "Marked read")

        guard isLiveGmailThread(previousThread) else { return }
        let newValue = updatedThread.isUnread
        Task { [weak self] in
            guard let self else { return }
            do {
                try await gmailIntegration.setUnread(newValue, threadID: id)
                if let updatedThread = thread(withID: id) {
                    try await gmailIntegration.persistLocalThreadState(updatedThread)
                }
            } catch {
                replaceThread(previousThread)
                toast("Read state failed: \(Self.userFacingMessage(for: error))")
            }
        }
    }

    func setReminder(at date: Date) {
        guard date.timeIntervalSinceNow > 30,
              let thread = commandTargetThread else {
            toast("Choose a future reminder time")
            return
        }

        reminderDates[thread.id] = date
        persistReminderDates()
        scheduleNextReminderWake()
        scheduleNotification(for: thread, at: date)
        rebuildCurrentMailboxThreads()
        refreshVisibleThreads()
        closeCommandPalette()

        if openedThreadID == thread.id {
            openedThreadID = nil
            clearReplyPresentation()
        }
        if selectedThreadID == thread.id { selectedThreadID = visibleThreads.first?.id }
        toast("Reminder set for \(Self.scheduleFormatter.string(from: date))")
    }

    func requestUnsubscribe() {
        guard let thread = commandTargetThread else {
            toast("This message has no standard unsubscribe option")
            return
        }
        if let method = thread.unsubscribeMethod {
            pendingUnsubscribe = PendingUnsubscribe(
                threadID: thread.id,
                sender: thread.sender,
                method: method
            )
            return
        }
        guard isLiveGmailThread(thread) else {
            toast("This message has no standard unsubscribe option")
            return
        }

        let threadID = thread.id
        toast("Checking unsubscribe options…")
        Task { [weak self] in
            guard let self else { return }
            do {
                let refreshed = try await gmailIntegration.fetchThread(id: threadID)
                replaceThread(refreshed, replacingID: threadID)
                guard let method = refreshed.unsubscribeMethod else {
                    toast("This sender has no standard unsubscribe option")
                    return
                }
                pendingUnsubscribe = PendingUnsubscribe(
                    threadID: refreshed.id,
                    sender: refreshed.sender,
                    method: method
                )
            } catch {
                toast("Could not check unsubscribe: \(Self.userFacingMessage(for: error))")
            }
        }
    }

    func cancelUnsubscribe() {
        pendingUnsubscribe = nil
    }

    func confirmUnsubscribe() {
        guard let request = pendingUnsubscribe else { return }
        pendingUnsubscribe = nil

        switch request.method {
        case let .oneClick(url):
            toast("Unsubscribing…")
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await gmailIntegration.unsubscribeOneClick(at: url)
                    toast("Unsubscribed from \(request.sender)")
                } catch {
                    toast(Self.userFacingMessage(for: error))
                }
            }
        case let .web(url):
            NSWorkspace.shared.open(url)
            toast("Unsubscribe page opened")
        case let .email(url):
            presentUnsubscribeDraft(from: url)
        }
    }

    func requestBlockSender() {
        guard let thread = commandTargetThread else {
            toast("Choose a sender to block")
            return
        }
        let address = SenderBlockPolicy.normalizedAddress(thread.email)
        guard !address.isEmpty else {
            toast("This sender has no usable email address")
            return
        }
        pendingSenderBlock = PendingSenderBlock(sender: thread.sender, email: address)
    }

    func cancelBlockSender() {
        pendingSenderBlock = nil
    }

    func confirmBlockSender() {
        guard let request = pendingSenderBlock else { return }
        pendingSenderBlock = nil
        let address = SenderBlockPolicy.normalizedAddress(request.email)
        guard !address.isEmpty else { return }

        let targetID = openedThreadID ?? selectedThreadID
        let targetIndex = targetID.flatMap { visibleThreadOffsetsByID[$0] } ?? 0
        let wasReadingBlockedSender = openedThread.map {
            SenderBlockPolicy.normalizedAddress($0.email) == address
        } ?? false
        let matchingThreads = threads.filter {
            SenderBlockPolicy.normalizedAddress($0.email) == address
        }

        blockedSenderAddresses.insert(address)
        persistBlockedSenderAddresses()
        for thread in matchingThreads {
            mutateThread(withID: thread.id) { updated in
                updated.folder = .archive
                updated.labels.remove(.inbox)
                updated.labels.insert(.archive)
                updated.gmailLabelIDs.remove("INBOX")
            }
        }

        if wasReadingBlockedSender {
            if !visibleThreads.isEmpty {
                let next = visibleThreads[min(targetIndex, visibleThreads.count - 1)]
                open(next)
            } else {
                closeThread()
                selectedThreadID = nil
            }
        } else if let targetID,
                  visibleThreadOffsetsByID[targetID] == nil {
            selectedThreadID = visibleThreads.indices.contains(targetIndex)
                ? visibleThreads[targetIndex].id
                : visibleThreads.last?.id
        }

        scheduleBlockedSenderArchives(
            matchingThreads.filter(isLiveGmailThread).map(\.id)
        )
        toast("Blocked (request.sender)")
    }

    func requestReply() {
        if openedThreadID == nil {
            openSelected()
        }
        guard let openedThreadID else { return }
        if replyFocusThreadID != openedThreadID {
            if !isReplyComposerPresented { isReplyComposerPresented = true }
            replyFocusThreadID = openedThreadID
        }
        replyFocusRequest += 1
        NotificationCenter.default.post(name: .focusReplyEditor, object: nil)
    }

    func sendReply() {
        let body = MailDraftSerializer.normalizedBody(from: replyDraft)
        let outgoingBody = MailDraftSerializer.outgoingText(from: replyDraft, inlineImages: replyInlineImages)
        let attachmentNames = replyAttachments.map(\.name)
        guard (!outgoingBody.isEmpty || !attachmentNames.isEmpty || !replyInlineImages.isEmpty),
              let id = openedThreadID,
              let previousThread = thread(withID: id) else { return }

        let previousDraft = replyDraft
        let previousAttachments = replyAttachments
        let previousInlineImages = replyInlineImages
        let isLive = isLiveGmailThread(previousThread)
        let lastMessage = previousThread.messages.last
        let gmailDraft = GmailOutgoingDraft(
            to: previousThread.email,
            subject: previousThread.subject.lowercased().hasPrefix("re:")
                ? previousThread.subject
                : "Re: \(previousThread.subject)",
            draftBody: previousDraft,
            attachments: previousAttachments,
            inlineImages: previousInlineImages,
            inReplyTo: lastMessage?.rfcMessageID,
            references: lastMessage?.references
        )

        var updatedThread = previousThread
        updatedThread.messages.append(
            MailMessage(
                id: "reply-\(UUID().uuidString)",
                sender: "You",
                senderEmail: "me",
                recipientLine: "to \(previousThread.sender)",
                body: body,
                timestamp: "Now",
                attachmentNames: attachmentNames,
                inlineImages: replyInlineImages,
                gmailLabelIDs: isLive ? ["SENT"] : []
            )
        )
        updatedThread.preview = outgoingBody.isEmpty
            ? "Attachment: \(attachmentNames.joined(separator: ", "))"
            : outgoingBody
        updatedThread.displayDate = "Now"
        updatedThread.isUnread = false
        updatedThread.hasAttachment = updatedThread.hasAttachment
            || !attachmentNames.isEmpty
            || !replyInlineImages.isEmpty
        replaceThread(updatedThread)
        replyDraft = ""
        replyAttachments = []
        replyInlineImages = []
        replyFormattingRequest = nil
        replyInlineImageRequest = nil

        let undoID = registerUndo(
            .reply(
                previousThread: previousThread,
                draft: previousDraft,
                attachments: previousAttachments,
                inlineImages: previousInlineImages
            ),
            message: "Reply sent"
        )
        pendingUndoTasks[undoID] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(MailUndoWindow.duration))
            } catch {
                return
            }
            guard let self, finalizePendingUndo(id: undoID), isLive else { return }
            let response: GmailSendResponse
            do {
                response = try await gmailIntegration.send(draft: gmailDraft, threadID: id)
            } catch {
                replaceThread(previousThread)
                if replyDraft.isEmpty {
                    replyDraft = previousDraft
                    replyAttachments = previousAttachments
                    replyInlineImages = previousInlineImages
                }
                toast("Send failed: \(Self.userFacingMessage(for: error))")
                return
            }

            do {
                let syncedThread = try await gmailIntegration.fetchThread(id: response.threadId)
                replaceThread(syncedThread, replacingID: id)
            } catch {
                startGmailSync(showSetupOnFailure: false)
            }
        }
    }

    func scheduleReply(at date: Date) {
        let outgoingBody = MailDraftSerializer.outgoingText(from: replyDraft, inlineImages: replyInlineImages)
        guard date > Date(), (!outgoingBody.isEmpty || !replyAttachments.isEmpty || !replyInlineImages.isEmpty), let threadID = openedThreadID else {
            toast("Write a reply and choose a future time")
            return
        }

        let payload: [String: Any] = [
            "threadID": threadID,
            "body": outgoingBody,
            "attachmentNames": replyAttachments.map(\.name),
            "inlineImageNames": replyInlineImages.map(\.name),
            "sendAt": date.timeIntervalSince1970
        ]
        UserDefaults.standard.set(payload, forKey: "keyboard-mail-scheduled-send")

        replyDraft = ""
        replyAttachments = []
        replyInlineImages = []
        replyFormattingRequest = nil
        replyInlineImageRequest = nil
        closeCommandPalette()
        toast("Scheduled for \(Self.scheduleFormatter.string(from: date))")
    }

    func addReplyAttachments(_ urls: [URL]) {
        replyAttachments = mergedAttachments(replyAttachments, adding: urls)
        loadAttachmentMetadata(for: replyAttachments, destination: .reply)
    }

    func removeReplyAttachment(_ attachment: DraftAttachment) {
        replyAttachments.removeAll { $0.id == attachment.id }
    }

    func embedReplyImages(_ urls: [URL]) {
        let images = urls.compactMap(InlineDraftImage.init(url:))
        guard !images.isEmpty else {
            toast("That image could not be embedded")
            return
        }
        replyInlineImageRequest = MailInlineImageRequest(images: images)
    }

    func formatReply(_ command: MailEditorCommand) {
        replyFormattingRequest = MailEditorRequest(command: command)
    }

    func presentCompose() {
        isComposePresented = true
        selectedComposeRecipientSuggestionIndex = 0
        suppressedRecipientSuggestionsForValue = nil
    }

    func closeCompose() {
        isComposePresented = false
        composeTo = ""
        composeSubject = ""
        composeBody = ""
        composeAttachments = []
        composeInlineImages = []
        composeFormattingRequest = nil
        composeInlineImageRequest = nil
        selectedComposeRecipientSuggestionIndex = 0
        suppressedRecipientSuggestionsForValue = nil
    }

    func sendCompose() {
        let to = composeTo.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = composeSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = MailDraftSerializer.normalizedBody(from: composeBody)
        let outgoingBody = MailDraftSerializer.outgoingText(from: composeBody, inlineImages: composeInlineImages)
        let attachmentNames = composeAttachments.map(\.name)
        guard !to.isEmpty, !subject.isEmpty,
              (!outgoingBody.isEmpty || !attachmentNames.isEmpty || !composeInlineImages.isEmpty) else { return }

        let previousBody = composeBody
        let previousAttachments = composeAttachments
        let previousInlineImages = composeInlineImages
        let isLive = gmailCanPerformRemoteActions
        let optimisticThreadID = "sent-\(UUID().uuidString)"
        let gmailDraft = GmailOutgoingDraft(
            to: to,
            subject: subject,
            draftBody: previousBody,
            attachments: previousAttachments,
            inlineImages: previousInlineImages,
            inReplyTo: nil,
            references: nil
        )

        let optimisticThread = MailThread(
                id: optimisticThreadID,
                sender: "You",
                email: to,
                subject: subject,
                preview: outgoingBody.isEmpty ? "Attachment: \(attachmentNames.joined(separator: ", "))" : outgoingBody,
                displayDate: "Now",
                date: Date(),
                isUnread: false,
                isStarred: false,
                hasAttachment: !attachmentNames.isEmpty || !composeInlineImages.isEmpty,
                folder: .sent,
                labels: [.sent],
                messages: [
                    MailMessage(
                        id: "message-\(UUID().uuidString)",
                        sender: "You",
                        senderEmail: "me",
                        recipientLine: "to \(to)",
                        body: body,
                        timestamp: "Now",
                        attachmentNames: attachmentNames,
                        inlineImages: composeInlineImages,
                        gmailLabelIDs: isLive ? ["SENT"] : []
                    )
                ],
                gmailLabelIDs: isLive ? ["SENT"] : []
            )
        insertThread(optimisticThread)
        closeCompose()
        let undoID = registerUndo(
            .compose(
                optimisticThreadID: optimisticThreadID,
                to: to,
                subject: subject,
                draft: previousBody,
                attachments: previousAttachments,
                inlineImages: previousInlineImages
            ),
            message: "Message sent"
        )
        pendingUndoTasks[undoID] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(MailUndoWindow.duration))
            } catch {
                return
            }
            guard let self, finalizePendingUndo(id: undoID), isLive else { return }
            let response: GmailSendResponse
            do {
                response = try await gmailIntegration.send(draft: gmailDraft)
            } catch {
                removeThread(withID: optimisticThreadID)
                composeTo = to
                composeSubject = subject
                composeBody = previousBody
                composeAttachments = previousAttachments
                composeInlineImages = previousInlineImages
                isComposePresented = true
                toast("Send failed: \(Self.userFacingMessage(for: error))")
                return
            }

            do {
                let syncedThread = try await gmailIntegration.fetchThread(id: response.threadId)
                if thread(withID: optimisticThreadID) != nil {
                    replaceThread(syncedThread, replacingID: optimisticThreadID)
                } else if thread(withID: syncedThread.id) == nil {
                    insertThread(syncedThread)
                }
            } catch {
                startGmailSync(showSetupOnFailure: false)
            }
        }
    }

    func addComposeAttachments(_ urls: [URL]) {
        composeAttachments = mergedAttachments(composeAttachments, adding: urls)
        loadAttachmentMetadata(for: composeAttachments, destination: .compose)
    }

    func removeComposeAttachment(_ attachment: DraftAttachment) {
        composeAttachments.removeAll { $0.id == attachment.id }
    }

    func embedComposeImages(_ urls: [URL]) {
        let images = urls.compactMap(InlineDraftImage.init(url:))
        guard !images.isEmpty else {
            toast("That image could not be embedded")
            return
        }
        composeInlineImageRequest = MailInlineImageRequest(images: images)
    }

    func formatCompose(_ command: MailEditorCommand) {
        composeFormattingRequest = MailEditorRequest(command: command)
    }

    @discardableResult
    private func registerUndo(_ action: UndoableMailAction, message: String) -> UUID {
        let pending = PendingUndoableMailAction(
            id: UUID(),
            window: MailUndoWindow(),
            action: action
        )
        pendingUndoActions.append(pending)
        toast("(message) · ⌘Z or Ctrl-Z to undo", duration: MailUndoWindow.duration)
        return pending.id
    }

    @discardableResult
    private func finalizePendingUndo(id: UUID) -> Bool {
        guard let index = pendingUndoActions.firstIndex(where: { $0.id == id }) else { return false }
        pendingUndoActions.remove(at: index)
        pendingUndoTasks[id] = nil
        return true
    }

    @discardableResult
    func undoLastAction() -> Bool {
        let now = Date()
        guard let index = pendingUndoActions.lastIndex(where: { $0.window.isActive(at: now) }) else {
            return false
        }
        let pending = pendingUndoActions.remove(at: index)
        pendingUndoTasks.removeValue(forKey: pending.id)?.cancel()

        switch pending.action {
        case let .archive(previousThread):
            replaceThread(previousThread)
            toast("Archive undone")

        case let .reply(previousThread, draft, attachments, inlineImages):
            replaceThread(previousThread)
            selectedThreadID = previousThread.id
            openedThreadID = previousThread.id
            replyDraft = draft
            replyAttachments = attachments
            replyInlineImages = inlineImages
            replyFormattingRequest = nil
            replyInlineImageRequest = nil
            requestReply()
            toast("Send undone")

        case let .compose(optimisticThreadID, to, subject, draft, attachments, inlineImages):
            removeThread(withID: optimisticThreadID)
            composeTo = to
            composeSubject = subject
            composeBody = draft
            composeAttachments = attachments
            composeInlineImages = inlineImages
            composeFormattingRequest = nil
            composeInlineImageRequest = nil
            presentCompose()
            toast("Send undone")
        }
        return true
    }

    func handleKeyEvent(_ event: NSEvent) -> Bool {
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if (modifiers.contains(.command) || modifiers.contains(.control)),
           !modifiers.contains(.shift),
           characters == "z",
           !event.isARepeat,
           undoLastAction() {
            return true
        }

        if pendingUnsubscribe != nil || pendingSenderBlock != nil {
            if event.keyCode == 36 || event.keyCode == 76 {
                if pendingUnsubscribe != nil { confirmUnsubscribe() }
                else { confirmBlockSender() }
                return true
            }
            if event.keyCode == 53 {
                cancelUnsubscribe()
                cancelBlockSender()
                return true
            }
            return false
        }

        if (modifiers.contains(.command) || modifiers.contains(.control)), characters == "k" {
            #if !PERFORMANCE_BENCHMARK
            if let textView = NativeMailTextView.activeEditor,
               textView.selectedRange().length > 0 {
                textView.requestLink()
                return true
            }
            #endif
            guard !event.isARepeat else { return true }
            presentCommandPalette()
            return true
        }

        if isCommandPalettePresented {
            if event.keyCode == 53 {
                if commandPaletteMode == .commands { closeCommandPalette() }
                else { commandPaletteMode = .commands }
                return true
            }

            guard commandPaletteMode == .commands else { return false }
            switch event.keyCode {
            case 125:
                moveCommandSelection(1)
                return true
            case 126:
                moveCommandSelection(-1)
                return true
            case 36, 76:
                executeSelectedCommand()
                return true
            default:
                // The palette can appear between two keystrokes. Preserve the
                // first typed character even if SwiftUI has not installed its
                // field editor as first responder yet; once focused, the native
                // text field handles input normally.
                guard !isTypingInTextControl else { return false }
                if event.keyCode == 51 {
                    if !commandQuery.isEmpty { commandQuery.removeLast() }
                    return true
                }
                guard !modifiers.contains(.command),
                      !modifiers.contains(.control),
                      !modifiers.contains(.option),
                      let typed = event.characters,
                      !typed.isEmpty,
                      typed.unicodeScalars.allSatisfy({
                          !CharacterSet.controlCharacters.contains($0)
                      }) else { return false }
                commandQuery.append(typed)
                return true
            }
        }

        if modifiers.contains(.command), (event.keyCode == 36 || event.keyCode == 76) {
            if isComposePresented { sendCompose() }
            else if openedThread != nil { sendReply() }
            return true
        }

        if event.keyCode == 53 {
            if isComposerOverlayPresented { return false }
            if Date().timeIntervalSince(lastComposerOverlayDismissal) < 0.4 { return true }
            if isComposePresented { closeCompose(); return true }
            if isSearchPresented { dismissSearch(); return true }
            if openedThread != nil { closeThread(); return true }
        }

        if isTypingInTextControl { return false }
        if modifiers.contains(.command), characters == "f" { requestSearch(); return true }

        if pendingGoKey, Date().timeIntervalSince(pendingGoDate) < 1.2 {
            pendingGoKey = false
            switch characters {
            case "i": selectMailbox(.inbox)
            case "s": selectMailbox(.starred)
            case "t": selectMailbox(.sent)
            case "d": selectMailbox(.drafts)
            case "a": selectMailbox(.archive)
            default: return false
            }
            return true
        }

        pendingGoKey = false
        switch characters {
        case "/": requestSearch(); return true
        case "c": presentCompose(); return true
        case "j": moveThreadSelection(1); return true
        case "k": moveThreadSelection(-1); return true
        case "e": archiveCurrent(); return true
        case "r": requestReply(); return true
        case "s": toggleStar(); return true
        case "u": toggleUnread(); return true
        case "g": pendingGoKey = true; pendingGoDate = Date(); return true
        default:
            if event.keyCode == 36 || event.keyCode == 76 { openSelected(); return true }
            return false
        }
    }

    private var isTypingInTextControl: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    private func matchesSelectedMailbox(_ thread: MailThread) -> Bool {
        switch selectedMailbox {
        case .inbox, .sent, .drafts, .archive:
            thread.folder == selectedMailbox || thread.labels.contains(selectedMailbox)
        case .starred:
            thread.isStarred
        case .updates, .receipts:
            thread.labels.contains(selectedMailbox)
        }
    }

    private func setUnread(_ isUnread: Bool, threadID: String) {
        guard let previousThread = thread(withID: threadID),
              previousThread.isUnread != isUnread else { return }
        mutateThread(withID: threadID) { thread in
            thread.isUnread = isUnread
            if isUnread { thread.gmailLabelIDs.insert("UNREAD") }
            else { thread.gmailLabelIDs.remove("UNREAD") }
        }

        guard isLiveGmailThread(previousThread) else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await gmailIntegration.setUnread(isUnread, threadID: threadID)
                if let updatedThread = thread(withID: threadID) {
                    try await gmailIntegration.persistLocalThreadState(updatedThread)
                }
            } catch {
                replaceThread(previousThread)
                toast("Read state failed: \(Self.userFacingMessage(for: error))")
            }
        }
    }

    private func isLiveGmailThread(_ thread: MailThread) -> Bool {
        !thread.gmailLabelIDs.isEmpty && gmailHasConfiguration
    }

    private var commandTargetThread: MailThread? {
        if let openedThread { return openedThread }
        guard let selectedThreadID else { return nil }
        return thread(withID: selectedThreadID)
    }

    private var gmailCanPerformRemoteActions: Bool {
        switch gmailConnectionState {
        case .connected, .syncing: true
        default: false
        }
    }

    private func mergedAttachments(_ current: [DraftAttachment], adding urls: [URL]) -> [DraftAttachment] {
        var merged = current
        var existingPaths = Set(current.map { $0.url.standardizedFileURL.path })

        for url in urls {
            let path = url.standardizedFileURL.path
            if existingPaths.insert(path).inserted {
                merged.append(DraftAttachment(url: url))
            }
        }

        return merged
    }

    private func presentUnsubscribeDraft(from url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            toast("The unsubscribe email address could not be opened")
            return
        }
        let recipient = url.path.removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !recipient.isEmpty else {
            toast("The unsubscribe email address is missing")
            return
        }

        let fields = Dictionary(
            (components.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
        presentCompose()
        composeTo = recipient
        composeSubject = fields["subject"]?.removingPercentEncoding ?? "Unsubscribe"
        composeBody = fields["body"]?.removingPercentEncoding ?? "Unsubscribe"
        toast("Unsubscribe draft created")
    }

    private func clearDueReminders() {
        let now = Date()
        let dueIDs = reminderDates.compactMap { threadID, date in
            date <= now ? threadID : nil
        }
        if !dueIDs.isEmpty {
            for threadID in dueIDs { reminderDates.removeValue(forKey: threadID) }
            persistReminderDates()
            rebuildCurrentMailboxThreads()
            refreshVisibleThreads()
        }
        scheduleNextReminderWake()
    }

    private func scheduleNextReminderWake() {
        reminderWakeTask?.cancel()
        guard let nextDate = reminderDates.values.filter({ $0 > Date() }).min() else {
            reminderWakeTask = nil
            return
        }
        let delay = max(1, nextDate.timeIntervalSinceNow)
        reminderWakeTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.clearDueReminders()
        }
    }

    private func persistReminderDates() {
        let values = reminderDates.mapValues(\.timeIntervalSince1970)
        UserDefaults.standard.set(values, forKey: Self.reminderDefaultsKey)
    }

    private func scheduleNotification(for thread: MailThread, at date: Date) {
        let identifier = "mail-reminder-\(thread.id)"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        Task {
            let settings = await center.notificationSettings()
            let authorized: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                authorized = true
            case .notDetermined:
                authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) == true
            default:
                authorized = false
            }
            guard authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = "Mail reminder"
            content.body = "\(thread.sender): \(thread.subject)"
            content.sound = .default
            content.userInfo = ["threadID": thread.id]
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, date.timeIntervalSinceNow),
                repeats: false
            )
            try? await center.add(
                UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            )
        }
    }

    private static func loadReminderDates() -> [String: Date] {
        guard let values = UserDefaults.standard.dictionary(forKey: reminderDefaultsKey) else { return [:] }
        return values.reduce(into: [:]) { result, entry in
            if let interval = entry.value as? Double {
                result[entry.key] = Date(timeIntervalSince1970: interval)
            } else if let number = entry.value as? NSNumber {
                result[entry.key] = Date(timeIntervalSince1970: number.doubleValue)
            }
        }
    }

    private func persistBlockedSenderAddresses() {
        UserDefaults.standard.set(
            blockedSenderAddresses.sorted(),
            forKey: Self.blockedSenderDefaultsKey
        )
    }

    private static func loadBlockedSenderAddresses() -> Set<String> {
        let addresses = UserDefaults.standard.stringArray(forKey: blockedSenderDefaultsKey) ?? []
        return Set(addresses.map(SenderBlockPolicy.normalizedAddress).filter { !$0.isEmpty })
    }

    private enum AttachmentDestination {
        case reply
        case compose
    }

    private func loadAttachmentMetadata(
        for attachments: [DraftAttachment],
        destination: AttachmentDestination
    ) {
        for attachment in attachments where attachment.byteCount == nil {
            guard loadingAttachmentMetadata.insert(attachment.id).inserted else { continue }
            let id = attachment.id
            let url = attachment.url

            Task { [weak self] in
                let byteCount = await Task.detached(priority: .utility) {
                    DraftAttachment.loadByteCount(for: url)
                }.value
                guard let self else { return }
                loadingAttachmentMetadata.remove(id)
                guard let byteCount else { return }

                switch destination {
                case .reply:
                    guard let index = replyAttachments.firstIndex(where: { $0.id == id }) else { return }
                    replyAttachments[index].byteCount = byteCount
                case .compose:
                    guard let index = composeAttachments.firstIndex(where: { $0.id == id }) else { return }
                    composeAttachments[index].byteCount = byteCount
                }
            }
        }
    }

    private func bootstrapGmail() async {
        let bootstrap = await gmailIntegration.bootstrap()
        PerformanceProbe.markPhase("cacheLoaded")
        gmailHasConfiguration = bootstrap.hasConfiguration
        if let directory = bootstrap.recipientDirectory {
            gmailRecipientDirectory = directory.entries
            gmailRecipientDirectorySyncedAt = directory.syncedAt
            gmailRecipientDirectoryStatus = "\(directory.entries.count) Gmail addresses ready"
        }
        if let cache = bootstrap.cache, !cache.threads.isEmpty {
            apply(cache)
        } else if !gmailRecipientDirectory.isEmpty {
            recipientAutocomplete.rebuild(
                threads: threads,
                directory: gmailRecipientDirectory
            )
        }

        guard bootstrap.hasConfiguration else {
            gmailConnectionState = .disconnected
            return
        }

        // Cached mail is the first usable state. Keychain authorization can
        // legitimately pause after an app update and must never hold it back.
        if let cache = bootstrap.cache {
            gmailConnectionState = .connected(email: cache.accountEmail, syncedAt: cache.syncedAt)
        } else {
            gmailConnectionState = .syncing(completed: 0, total: 0)
        }

        if await gmailIntegration.restoreStoredCredentials() {
            startGmailSync(showSetupOnFailure: false)
        } else {
            gmailConnectionState = .readyToConnect
        }
    }

    private func startGmailSync(
        showSetupOnFailure: Bool,
        forceRecipientDirectoryRefresh: Bool = false
    ) {
        guard gmailSyncTask == nil else { return }
        gmailSyncTask = Task { [weak self] in
            guard let self else { return }
            defer { gmailSyncTask = nil }
            do {
                let snapshot = try await gmailIntegration.sync { [weak self] completed, total in
                    await self?.updateGmailSyncProgress(completed: completed, total: total)
                }
                apply(snapshot)
                gmailConnectionState = .connected(email: snapshot.accountEmail, syncedAt: snapshot.syncedAt)
                refreshGmailRecipientDirectoryIfNeeded(force: forceRecipientDirectoryRefresh)
            } catch {
                gmailConnectionState = .failed(message: Self.userFacingMessage(for: error))
                if showSetupOnFailure { isGmailSetupPresented = true }
            }
        }
    }

    private func apply(_ snapshot: GmailCachedMailbox) {
        PerformanceProbe.markPhase("applySnapshotBegan")
        let previousSelection = selectedThreadID
        let previousOpenThread = openedThreadID
        let snapshotContainsBodies = snapshot.threads.contains { !$0.messages.isEmpty }
        replaceAllThreads(
            snapshotContainsBodies ? snapshot.threads.map(\.listSummary) : snapshot.threads
        )

        if let previousSelection, thread(withID: previousSelection) != nil {
            selectedThreadID = previousSelection
        } else {
            selectedThreadID = visibleThreads.first?.id ?? threads.first?.id
        }

        if let previousOpenThread, thread(withID: previousOpenThread) != nil {
            openedThreadID = previousOpenThread
        } else {
            openedThreadID = nil
        }

        if let openedThread {
            if openedThread.messages.isEmpty {
                if let hydrated = hydratedThreadForOpening(threadID: openedThread.id) {
                    replaceThread(hydrated, replacingID: openedThread.id)
                    hydrateInlineContentIfNeeded(hydrated)
                } else {
                    hydrateCachedThreadIfNeeded(threadID: openedThread.id)
                }
            } else {
                hydrateInlineContentIfNeeded(openedThread)
            }
        } else if let selectedThreadID {
            hydrateCachedThreadIfNeeded(threadID: selectedThreadID)
        }
        PerformanceProbe.markPhase("applySnapshotFinished")
    }

    private func refreshGmailRecipientDirectoryIfNeeded(force: Bool = false) {
        guard gmailCanPerformRemoteActions, gmailRecipientDirectoryTask == nil else { return }
        let refreshInterval: TimeInterval = 7 * 24 * 60 * 60
        if !force,
           let syncedAt = gmailRecipientDirectorySyncedAt,
           Date().timeIntervalSince(syncedAt) < refreshInterval { return }

        let hadCachedDirectory = !gmailRecipientDirectory.isEmpty
        gmailRecipientDirectoryStatus = "Starting Gmail correspondent scan…"
        gmailRecipientDirectoryTask = Task { [weak self] in
            guard let self else { return }
            defer { gmailRecipientDirectoryTask = nil }
            do {
                let snapshot = try await gmailIntegration.syncRecipientDirectory { [weak self] completed, total in
                    await self?.updateGmailRecipientDirectoryProgress(
                        completed: completed,
                        total: total
                    )
                }
                gmailRecipientDirectory = snapshot.entries
                gmailRecipientDirectorySyncedAt = snapshot.syncedAt
                gmailRecipientDirectoryStatus = "\(snapshot.entries.count) Gmail addresses ready"
                recipientAutocomplete.rebuild(
                    threads: threads,
                    directory: snapshot.entries
                )
                if force || !hadCachedDirectory {
                    toast("\(snapshot.entries.count) Gmail addresses ready")
                }
            } catch is CancellationError {
                return
            } catch {
                gmailRecipientDirectoryStatus = "Address scan failed: \(Self.userFacingMessage(for: error))"
                if force || !hadCachedDirectory {
                    toast("Could not finish loading Gmail addresses")
                }
            }
        }
    }

    private func updateGmailRecipientDirectoryProgress(completed: Int, total: Int) {
        guard completed == 0 || completed == total || completed.isMultiple(of: 250) else { return }
        gmailRecipientDirectoryStatus = total > 0
            ? "Loading Gmail correspondents: \(completed) of \(total) conversations"
            : "Starting Gmail correspondent scan…"
    }

    private func hydrateInlineContentIfNeeded(_ thread: MailThread) {
        let hasUnresolvedContentID = thread.messages.contains { message in
            message.htmlBody?.localizedCaseInsensitiveContains("cid:") == true
        }
        guard hasUnresolvedContentID,
              isLiveGmailThread(thread),
              hydratingThreadIDs.insert(thread.id).inserted else { return }

        let threadID = thread.id
        Task { [weak self] in
            guard let self else { return }
            defer { hydratingThreadIDs.remove(threadID) }
            guard let hydratedThread = try? await gmailIntegration.fetchThread(
                id: threadID,
                includeInlineContent: true
            ), self.thread(withID: threadID) != nil else { return }
            replaceThread(hydratedThread, replacingID: threadID)
        }
    }

    private func hydrateCachedThreadIfNeeded(threadID: String) {
        guard cachedSearchEnabled,
              hydratedThreadCache[threadID] == nil,
              loadingCachedThreadIDs.insert(threadID).inserted else { return }
        threadBodyLoadErrors[threadID] = nil
        Task { [weak self] in
            guard let self else { return }
            defer { loadingCachedThreadIDs.remove(threadID) }
            do {
                let cached = try await gmailIntegration.cachedThread(id: threadID)
                var hydrated: MailThread
                if let cached, !cached.messages.isEmpty {
                    hydrated = cached
                } else {
                    guard gmailCanPerformRemoteActions else {
                        throw GmailIntegrationError.cache("The full message is not available offline.")
                    }
                    // A summary-only row can exist after a cache migration or
                    // a remote search. Fetching one thread is fast and repairs
                    // that SQLite row for every later open.
                    hydrated = try await gmailIntegration.fetchThread(id: threadID)
                }

                guard let current = thread(withID: threadID), !hydrated.messages.isEmpty else {
                    throw GmailIntegrationError.invalidServerResponse
                }
                hydrated.folder = current.folder
                hydrated.labels = current.labels
                hydrated.isUnread = current.isUnread
                hydrated.isStarred = current.isStarred
                hydrated.gmailLabelIDs = current.gmailLabelIDs
                cacheHydratedThread(hydrated)
                threadBodyLoadErrors[threadID] = nil
                guard openedThreadID == threadID else { return }
                replaceThread(hydrated, replacingID: threadID)
                hydrateInlineContentIfNeeded(hydrated)
            } catch {
                guard openedThreadID == threadID else { return }
                threadBodyLoadErrors[threadID] = Self.userFacingMessage(for: error)
            }
        }
    }

    func retryLoadingThreadBody(_ threadID: String) {
        threadBodyLoadErrors[threadID] = nil
        hydratedThreadCache[threadID] = nil
        hydrateCachedThreadIfNeeded(threadID: threadID)
    }

    private func hydratedThreadForOpening(threadID: String) -> MailThread? {
        guard var cached = hydratedThreadCache[threadID],
              let current = thread(withID: threadID) else { return nil }
        cached.folder = current.folder
        cached.labels = current.labels
        cached.isUnread = current.isUnread
        cached.isStarred = current.isStarred
        cached.gmailLabelIDs = current.gmailLabelIDs
        return cached
    }

    private func cacheHydratedThread(_ thread: MailThread) {
        hydratedThreadCache[thread.id] = thread
        hydratedThreadCacheOrder.removeAll { $0 == thread.id }
        hydratedThreadCacheOrder.append(thread.id)
        while hydratedThreadCacheOrder.count > 12 {
            let evicted = hydratedThreadCacheOrder.removeFirst()
            hydratedThreadCache.removeValue(forKey: evicted)
        }
    }

    private func thread(withID id: String) -> MailThread? {
        guard let offset = threadOffsetsByID[id], threads.indices.contains(offset) else { return nil }
        let thread = threads[offset]
        return thread.id == id ? thread : nil
    }

    private func rebuildThreadCaches() {
        threadOffsetsByID = Dictionary(
            uniqueKeysWithValues: threads.enumerated().map { ($0.element.id, $0.offset) }
        )
        rebuildCurrentMailboxThreads()
        refreshCounts()
        refreshVisibleThreads()
        refreshPaletteMailResults()
        recipientAutocomplete.rebuild(
            threads: threads,
            directory: gmailRecipientDirectory
        )
    }

    private func replaceAllThreads(_ replacement: [MailThread]) {
        let (policyAdjusted, newlyBlockedInboxIDs) = applyingBlockedSenderPolicy(to: replacement)
        if zip(policyAdjusted, policyAdjusted.dropFirst()).allSatisfy({ $0.0.date >= $0.1.date }) {
            threads = policyAdjusted
        } else {
            threads = policyAdjusted.sorted { $0.date > $1.date }
        }
        isSearchIndexReady = false
        hydratedThreadCache.removeAll(keepingCapacity: true)
        hydratedThreadCacheOrder.removeAll(keepingCapacity: true)
        pendingSearchMetadata.removeAll(keepingCapacity: true)
        pendingSearchReplacements.removeAll(keepingCapacity: true)
        pendingSearchRemovals.removeAll(keepingCapacity: true)
        rebuildThreadCaches()
        scheduleSearchIndexRebuild(debounceMilliseconds: 500)
        scheduleBlockedSenderArchives(newlyBlockedInboxIDs)
    }

    private func applyingBlockedSenderPolicy(
        to replacement: [MailThread]
    ) -> (threads: [MailThread], inboxThreadIDs: [String]) {
        guard !blockedSenderAddresses.isEmpty else { return (replacement, []) }
        var inboxThreadIDs: [String] = []
        let adjusted = replacement.map { thread -> MailThread in
            let address = SenderBlockPolicy.normalizedAddress(thread.email)
            guard blockedSenderAddresses.contains(address),
                  thread.folder == .inbox || thread.gmailLabelIDs.contains("INBOX") else {
                return thread
            }
            var blocked = thread
            if blocked.gmailLabelIDs.contains("INBOX") { inboxThreadIDs.append(blocked.id) }
            blocked.folder = .archive
            blocked.labels.remove(.inbox)
            blocked.labels.insert(.archive)
            blocked.gmailLabelIDs.remove("INBOX")
            return blocked
        }
        return (adjusted, inboxThreadIDs)
    }

    private func scheduleBlockedSenderArchives(_ threadIDs: [String]) {
        guard gmailHasConfiguration else { return }
        let unscheduled = Set(threadIDs).subtracting(archivingBlockedThreadIDs)
        guard !unscheduled.isEmpty else { return }
        archivingBlockedThreadIDs.formUnion(unscheduled)

        Task { [weak self] in
            guard let self else { return }
            for threadID in unscheduled {
                do {
                    try await gmailIntegration.archive(threadID: threadID)
                    if let updatedThread = thread(withID: threadID) {
                        try await gmailIntegration.persistLocalThreadState(updatedThread)
                    }
                } catch {
                    // Keep the local block effective. A later Gmail sync retries
                    // any thread that still carries the remote INBOX label.
                }
                archivingBlockedThreadIDs.remove(threadID)
            }
        }
    }

    private func mutateThread(withID id: String, _ mutation: (inout MailThread) -> Void) {
        guard let offset = threadOffsetsByID[id], threads.indices.contains(offset) else { return }
        let previous = threads[offset]
        var updated = previous
        mutation(&updated)
        threads[offset] = updated
        if isSearchIndexReady {
            searchIndex.updateMetadata(for: updated)
        } else {
            pendingSearchMetadata[id] = updated
        }
        updateCounts(previous: previous, updated: updated)
        updateCurrentMailboxThreads(previous: previous, updated: updated)
        updateVisibleThreads()
        refreshPaletteAfterMutation()
    }

    private func replaceThread(_ replacement: MailThread, replacingID: String? = nil) {
        let oldID = replacingID ?? replacement.id
        guard let offset = threadOffsetsByID[oldID], threads.indices.contains(offset) else {
            if thread(withID: replacement.id) == nil { insertThread(replacement) }
            return
        }

        let previous = threads[offset]
        threads[offset] = replacement

        if openedThreadID == oldID || openedThreadID == replacement.id {
            if replyFocusThreadID == oldID { replyFocusThreadID = replacement.id }
            let shouldPresent = replacement.shouldOpenReplyComposerByDefault
            if replyFocusThreadID == nil,
               isReplyComposerPresented != shouldPresent {
                isReplyComposerPresented = shouldPresent
            }
        }

        if previous.date != replacement.date {
            threads.sort { $0.date > $1.date }
            threadOffsetsByID = Dictionary(
                uniqueKeysWithValues: threads.enumerated().map { ($0.element.id, $0.offset) }
            )
        } else if previous.id != replacement.id {
            threadOffsetsByID.removeValue(forKey: previous.id)
            threadOffsetsByID[replacement.id] = offset
        }
        if isSearchIndexReady {
            if previous.id != replacement.id { searchIndex.remove(threadID: previous.id) }
            searchIndex.update(replacement)
        } else {
            if previous.id != replacement.id { pendingSearchRemovals.insert(previous.id) }
            pendingSearchReplacements[replacement.id] = replacement
        }
        updateCounts(previous: previous, updated: replacement)
        updateCurrentMailboxThreads(previous: previous, updated: replacement)
        updateVisibleThreads()
        refreshPaletteAfterMutation()
    }

    private func configureReplyPresentation(for thread: MailThread) {
        let shouldPresent = thread.shouldOpenReplyComposerByDefault
        if isReplyComposerPresented != shouldPresent {
            isReplyComposerPresented = shouldPresent
        }
        if replyFocusThreadID != nil { replyFocusThreadID = nil }
    }

    private func clearReplyPresentation() {
        if isReplyComposerPresented { isReplyComposerPresented = false }
        if replyFocusThreadID != nil { replyFocusThreadID = nil }
    }

    private func insertThread(_ thread: MailThread) {
        guard self.thread(withID: thread.id) == nil else {
            replaceThread(thread)
            return
        }
        let insertionIndex = threads.firstIndex { $0.date < thread.date } ?? threads.endIndex
        threads.insert(thread, at: insertionIndex)
        recipientAutocomplete.record(thread)
        if isSearchIndexReady {
            searchIndex.update(thread)
        } else {
            pendingSearchReplacements[thread.id] = thread
            pendingSearchRemovals.remove(thread.id)
        }
        threadOffsetsByID = Dictionary(
            uniqueKeysWithValues: threads.enumerated().map { ($0.element.id, $0.offset) }
        )
        updateCounts(previous: nil, updated: thread)
        updateCurrentMailboxThreads(previous: nil, updated: thread)
        updateVisibleThreads()
        refreshPaletteAfterMutation()
    }

    private func removeThread(withID id: String) {
        guard let offset = threadOffsetsByID[id], threads.indices.contains(offset) else { return }
        let previous = threads.remove(at: offset)
        recipientAutocomplete.rebuild(
            threads: threads,
            directory: gmailRecipientDirectory
        )
        hydratedThreadCache.removeValue(forKey: id)
        hydratedThreadCacheOrder.removeAll { $0 == id }
        if isSearchIndexReady {
            searchIndex.remove(threadID: id)
        } else {
            pendingSearchRemovals.insert(id)
            pendingSearchMetadata.removeValue(forKey: id)
            pendingSearchReplacements.removeValue(forKey: id)
        }
        threadOffsetsByID = Dictionary(
            uniqueKeysWithValues: threads.enumerated().map { ($0.element.id, $0.offset) }
        )
        updateCounts(previous: previous, updated: nil)
        updateCurrentMailboxThreads(previous: previous, updated: nil)
        updateVisibleThreads()
        refreshPaletteAfterMutation()
    }

    private func refreshCounts() {
        unreadCount = threads.reduce(into: 0) { count, thread in
            if thread.folder == .inbox && thread.isUnread { count += 1 }
        }
        draftCount = threads.reduce(into: 0) { count, thread in
            if thread.folder == .drafts || thread.labels.contains(.drafts) { count += 1 }
        }
    }

    private func updateCounts(previous: MailThread?, updated: MailThread?) {
        let unreadDelta = inboxUnreadContribution(updated) - inboxUnreadContribution(previous)
        if unreadDelta != 0 { unreadCount += unreadDelta }

        let draftDelta = draftContribution(updated) - draftContribution(previous)
        if draftDelta != 0 { draftCount += draftDelta }
    }

    private func inboxUnreadContribution(_ thread: MailThread?) -> Int {
        guard let thread, thread.folder == .inbox, thread.isUnread else { return 0 }
        return 1
    }

    private func draftContribution(_ thread: MailThread?) -> Int {
        guard let thread,
              thread.folder == .drafts || thread.labels.contains(.drafts) else { return 0 }
        return 1
    }

    private func refreshPaletteAfterMutation() {
        guard !commandQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        refreshPaletteMailResults()
    }

    private func rebuildCurrentMailboxThreads() {
        let now = Date()
        currentMailboxThreads = threads.filter { isVisibleInCurrentMailbox($0, now: now) }
        rebuildCurrentMailboxOffsets()
    }

    private func updateCurrentMailboxThreads(previous: MailThread?, updated: MailThread?) {
        let now = Date()
        let previousWasVisible = previous.map { isVisibleInCurrentMailbox($0, now: now) } ?? false
        let updatedIsVisible = updated.map { isVisibleInCurrentMailbox($0, now: now) } ?? false

        switch (previousWasVisible, updatedIsVisible) {
        case (true, true):
            guard let previous, let updated,
                  let offset = currentMailboxThreadOffsetsByID[previous.id],
                  currentMailboxThreads.indices.contains(offset) else {
                rebuildCurrentMailboxThreads()
                return
            }
            if previous.id == updated.id, previous.date == updated.date {
                currentMailboxThreads[offset] = updated
            } else {
                currentMailboxThreads.remove(at: offset)
                insertVisibleThread(updated, into: &currentMailboxThreads)
                rebuildCurrentMailboxOffsets()
            }
        case (true, false):
            guard let previous,
                  let offset = currentMailboxThreadOffsetsByID[previous.id],
                  currentMailboxThreads.indices.contains(offset) else {
                rebuildCurrentMailboxThreads()
                return
            }
            currentMailboxThreads.remove(at: offset)
            rebuildCurrentMailboxOffsets()
        case (false, true):
            guard let updated else { return }
            insertVisibleThread(updated, into: &currentMailboxThreads)
            rebuildCurrentMailboxOffsets()
        case (false, false):
            return
        }
    }

    private func rebuildCurrentMailboxOffsets() {
        currentMailboxThreadOffsetsByID = Dictionary(
            uniqueKeysWithValues: currentMailboxThreads.enumerated().map { ($0.element.id, $0.offset) }
        )
        currentMailboxThreadIDs = Set(currentMailboxThreadOffsetsByID.keys)
    }

    private func updateVisibleThreads() {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setVisibleThreadsFromCurrentMailbox()
        } else {
            refreshVisibleThreads()
        }
    }

    private func insertVisibleThread(_ thread: MailThread, into list: inout [MailThread]) {
        let insertionIndex = list.firstIndex { $0.date < thread.date } ?? list.endIndex
        list.insert(thread, at: insertionIndex)
    }

    private func isVisibleInCurrentMailbox(_ thread: MailThread, now: Date) -> Bool {
        matchesSelectedMailbox(thread)
            && !(reminderDates[thread.id].map { $0 > now } ?? false)
    }

    private func setVisibleThreads(_ replacement: [MailThread]) {
        visibleThreadOffsetsByID = Dictionary(
            uniqueKeysWithValues: replacement.enumerated().map { ($0.element.id, $0.offset) }
        )
        visibleThreads = replacement
    }

    private func setVisibleThreadsFromCurrentMailbox() {
        visibleThreadOffsetsByID = currentMailboxThreadOffsetsByID
        visibleThreads = currentMailboxThreads
    }

    private func refreshVisibleThreads() {
        visibleSearchTask?.cancel()
        visibleSearchGeneration += 1
        let generation = visibleSearchGeneration
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            setVisibleThreadsFromCurrentMailbox()
            return
        }
        if cachedSearchEnabled, !query.contains(":") {
            startCachedVisibleSearchIfAvailable(
                query: query,
                allowedThreadIDs: currentMailboxThreadIDs,
                generation: generation
            )
            return
        }
        guard isSearchIndexReady else {
            startCachedVisibleSearchIfAvailable(
                query: query,
                allowedThreadIDs: currentMailboxThreadIDs,
                generation: generation
            )
            return
        }

        let allowedThreadIDs = currentMailboxThreadIDs
        let index = searchIndex
        visibleSearchTask = Task { [weak self] in
            let results = await Task.detached(priority: .userInitiated) {
                index.search(query, allowedThreadIDs: allowedThreadIDs)
            }.value
            guard !Task.isCancelled,
                  let self,
                  generation == visibleSearchGeneration,
                  query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            setVisibleThreads(results.compactMap { result in
                self.thread(withID: result.threadID)
            })
            if selectedThreadID.flatMap({ self.visibleThreadOffsetsByID[$0] }) == nil {
                selectedThreadID = visibleThreads.first?.id
            }
        }
    }

    private func refreshPaletteMailResults() {
        paletteSearchTask?.cancel()
        paletteSearchGeneration += 1
        let generation = paletteSearchGeneration
        let query = commandQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            if !paletteMailResults.isEmpty { paletteMailResults = [] }
            return
        }
        if cachedSearchEnabled, !query.contains(":") {
            paletteMailResults = []
            startCachedPaletteSearchIfAvailable(query: query, generation: generation)
            return
        }
        guard isSearchIndexReady else {
            paletteMailResults = []
            startCachedPaletteSearchIfAvailable(query: query, generation: generation)
            return
        }

        let index = searchIndex
        paletteSearchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(24))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let results = await Task.detached(priority: .userInitiated) {
                index.search(query, limit: 6)
            }.value
            guard !Task.isCancelled,
                  let self,
                  generation == paletteSearchGeneration,
                  query == commandQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            paletteMailResults = results.compactMap { result in
                self.thread(withID: result.threadID)
            }
        }
    }

    private func scheduleSearchIndexRebuild(debounceMilliseconds: Int = 0) {
        searchIndexGeneration += 1
        let generation = searchIndexGeneration
        let snapshot = threads
        searchIndexTask?.cancel()
        searchIndexTask = Task { [weak self] in
            if debounceMilliseconds > 0 {
                do {
                    try await Task.sleep(for: .milliseconds(debounceMilliseconds))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            var rebuilt = await Task.detached(priority: .utility) {
                MailSearchEngine.Index(threads: snapshot)
            }.value
            guard !Task.isCancelled,
                  let self,
                  generation == searchIndexGeneration else { return }
            for threadID in pendingSearchRemovals {
                rebuilt.remove(threadID: threadID)
            }
            for thread in pendingSearchReplacements.values {
                rebuilt.update(thread)
            }
            for (threadID, thread) in pendingSearchMetadata where pendingSearchReplacements[threadID] == nil {
                rebuilt.updateMetadata(for: thread)
            }
            pendingSearchRemovals.removeAll(keepingCapacity: true)
            pendingSearchReplacements.removeAll(keepingCapacity: true)
            pendingSearchMetadata.removeAll(keepingCapacity: true)
            searchIndex = rebuilt
            isSearchIndexReady = true
            PerformanceProbe.markPhase("searchIndexReady")
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                refreshVisibleThreads()
            }
            refreshPaletteAfterMutation()
        }
    }

    private func startCachedVisibleSearchIfAvailable(
        query: String,
        allowedThreadIDs: Set<String>,
        generation: Int
    ) {
        guard cachedSearchEnabled, !query.contains(":") else { return }
        visibleSearchTask = Task { [weak self] in
            guard let self,
                  let cachedIDs = try? await gmailIntegration.searchCachedMailIDs(query, limit: 500),
                  !Task.isCancelled,
                  generation == visibleSearchGeneration,
                  query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            setVisibleThreads(cachedIDs.compactMap { threadID in
                guard allowedThreadIDs.contains(threadID) else { return nil }
                return self.thread(withID: threadID)
            })
            if selectedThreadID.flatMap({ self.visibleThreadOffsetsByID[$0] }) == nil {
                selectedThreadID = visibleThreads.first?.id
            }
        }
    }

    private func startCachedPaletteSearchIfAvailable(query: String, generation: Int) {
        guard cachedSearchEnabled, !query.contains(":") else { return }
        paletteSearchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(24))
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  let cachedIDs = try? await gmailIntegration.searchCachedMailIDs(query, limit: 6),
                  !Task.isCancelled,
                  generation == paletteSearchGeneration,
                  query == commandQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            paletteMailResults = cachedIDs.compactMap { self.thread(withID: $0) }
        }
    }

    func prepareSearchIndexForBenchmark() async {
        if !isSearchIndexReady, searchIndexTask == nil {
            scheduleSearchIndexRebuild()
        }
        await searchIndexTask?.value
    }

    func awaitVisibleSearchForBenchmark() async {
        await visibleSearchTask?.value
    }

    func awaitPaletteSearchForBenchmark() async {
        await paletteSearchTask?.value
    }

    private func updateGmailSyncProgress(completed: Int, total: Int) {
        gmailConnectionState = .syncing(completed: completed, total: total)
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private func toast(_ message: String, duration: TimeInterval = 1.5) {
        toastClearTask?.cancel()
        toastMessage = message
        toastClearTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(duration))
            } catch {
                return
            }
            guard let self, self.toastMessage == message else { return }
            self.toastMessage = nil
            self.toastClearTask = nil
        }
    }

    func showToast(_ message: String) {
        toast(message)
    }

    private static let scheduleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        return formatter
    }()

    private static let reminderDefaultsKey = "keyboard-mail-reminder-dates"
    private static let blockedSenderDefaultsKey = "keyboard-mail-blocked-sender-addresses"
}
