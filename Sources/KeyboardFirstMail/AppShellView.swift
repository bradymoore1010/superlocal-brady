import AppKit
import SwiftUI

struct AppShellView: View {
    @Bindable var store: MailStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView(store: store)

                ZStack {
                    InboxView(store: store)
                        .opacity(store.openedThread == nil ? 1 : 0)
                        .allowsHitTesting(store.openedThread == nil)
                        .accessibilityHidden(store.openedThread != nil)

                    if let thread = store.openedThread {
                        ThreadView(store: store, thread: thread)
                    }
                }
            }
            .background(MailTheme.windowSurface)
            .ignoresSafeArea(.container, edges: .top)
            .allowsHitTesting(
                !store.isCommandPalettePresented
                    && !store.isComposePresented
                    && !store.isGmailSetupPresented
            )

            Group {
                if store.isComposePresented || store.isCommandPalettePresented || store.isGmailSetupPresented {
                    MailTheme.darkControl.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture {
                            if store.isCommandPalettePresented { store.closeCommandPalette() }
                            else if store.isGmailSetupPresented { store.closeGmailSetup() }
                            else { store.closeCompose() }
                        }
                }
            }
            .animation(layerAnimation, value: store.isComposePresented || store.isCommandPalettePresented || store.isGmailSetupPresented)

            Group {
                if store.isComposePresented {
                    ComposeView(store: store)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(layerAnimation, value: store.isComposePresented)

            Group {
                if store.isCommandPalettePresented {
                    CommandPaletteView(store: store)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(layerAnimation, value: store.isCommandPalettePresented)

            Group {
                if store.isGmailSetupPresented {
                    GmailConnectionView(store: store)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(layerAnimation, value: store.isGmailSetupPresented)

            Group {
                if let toast = store.toastMessage {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(MailTheme.font(13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(MailTheme.darkControl)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                            }
                            .shadow(color: MailTheme.darkControl.opacity(0.24), radius: 16, x: 0, y: 8)
                            .padding(.bottom, 20)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
        }
        .background { MailTheme.desktopBackdrop }
        .background(WindowConfigurationRepresentable())
        .background(KeyEventMonitor(store: store).frame(width: 0, height: 0))
        .preferredColorScheme(.light)
        .onAppear {
            PerformanceProbe.viewAppeared(store: store)
        }
        .onChange(of: store.threads.count) { _, _ in
            PerformanceProbe.viewAppeared(store: store)
        }
        .alert(
            store.pendingUnsubscribe?.confirmationTitle ?? "Unsubscribe?",
            isPresented: Binding(
                get: { store.pendingUnsubscribe != nil },
                set: { isPresented in
                    if !isPresented { store.cancelUnsubscribe() }
                }
            )
        ) {
            if let request = store.pendingUnsubscribe {
                Button(
                    request.confirmationButtonTitle,
                    role: request.isDestructive ? .destructive : nil
                ) {
                    store.confirmUnsubscribe()
                }
                .keyboardShortcut(.defaultAction)
            }
            Button("Cancel", role: .cancel) {
                store.cancelUnsubscribe()
            }
        } message: {
            Text(store.pendingUnsubscribe?.confirmationMessage ?? "")
        }
        .alert(
            store.pendingSenderBlock?.confirmationTitle ?? "Block sender?",
            isPresented: Binding(
                get: { store.pendingSenderBlock != nil },
                set: { isPresented in
                    if !isPresented { store.cancelBlockSender() }
                }
            )
        ) {
            Button("Block sender", role: .destructive) {
                store.confirmBlockSender()
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                store.cancelBlockSender()
            }
        } message: {
            Text(store.pendingSenderBlock?.confirmationMessage ?? "")
        }
    }

    private var layerAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.10, extraBounce: 0)
    }
}

private final class WindowConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("mail-main-window")
        MailWindowRegistry.mainWindow = window
    }
}

private struct WindowConfigurationRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowConfigurationView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct KeyEventMonitor: NSViewRepresentable {
    let store: MailStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.store = store
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        var store: MailStore
        private var monitor: Any?

        init(store: MailStore) {
            self.store = store
        }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.store.handleKeyEvent(event) ? nil : event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
