import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class MailApplicationDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        UNUserNotificationCenter.current().delegate = self
        if let icon = KeyboardMailBrandAssets.dockIcon {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            AttachmentPickerController.shared.prewarm()
            GmailCredentialPickerController.shared.prewarm()
            MailHTMLWebViewPool.prewarm()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        reopenMainWindow(in: sender)
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard let application = notification.object as? NSApplication,
              !application.windows.contains(where: \.isVisible) else { return }
        reopenMainWindow(in: application)
    }

    private func reopenMainWindow(in application: NSApplication) {
        guard let window = MailWindowRegistry.mainWindow ?? application.windows.first(where: { window in
            window.identifier?.rawValue == "mail-main-window"
        }) ?? application.windows.first(where: { !($0 is NSPanel) }) else { return }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
    }
}

#if !PERFORMANCE_BENCHMARK
@main
struct KeyboardFirstMailApp: App {
    @NSApplicationDelegateAdaptor(MailApplicationDelegate.self) private var appDelegate
    @State private var store: MailStore

    init() {
        PerformanceProbe.beginLaunch()
        if let threadCount = PerformanceProbe.fixtureThreadCount {
            _store = State(
                initialValue: MailStore(
                    initialThreads: PerformanceInboxFixture.make(threadCount: threadCount),
                    bootstrapGmail: false,
                    enableCachedSearch: false
                )
            )
        } else {
            _store = State(initialValue: MailStore())
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(store: store)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1100, height: 720)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Compose Message") { store.presentCompose() }
                    .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Mail") {
                Button("Command Menu") { store.presentCommandPalette() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Search Mail") { store.requestSearch() }
                    .keyboardShortcut("f", modifiers: .command)
                Divider()
                Button("Archive Current") { store.archiveCurrent() }
                Button("Reply") { store.requestReply() }
                Button("Toggle Star") { store.toggleStar() }
                Button("Mark Read or Unread") { store.toggleUnread() }
            }
        }
    }
}
#endif
