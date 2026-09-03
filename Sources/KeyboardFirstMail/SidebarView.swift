import SwiftUI

struct SidebarView: View {
    @Bindable var store: MailStore

    private let primaryMailboxes: [Mailbox] = [.inbox, .starred, .sent, .drafts, .archive]
    private let labelMailboxes: [Mailbox] = [.updates, .receipts]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                VStack(spacing: 2) {
                    ForEach(primaryMailboxes) { mailbox in
                        SidebarRow(store: store, mailbox: mailbox)
                    }
                }

                VStack(spacing: 2) {
                    Text("Labels")
                        .font(MailTheme.font(12))
                        .foregroundStyle(MailTheme.faintText)
                        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                        .padding(.horizontal, 10)

                    ForEach(labelMailboxes) { mailbox in
                        SidebarRow(store: store, mailbox: mailbox)
                    }
                }
            }

            Spacer(minLength: 24)

            VStack(spacing: 8) {
                Button(action: store.presentGmailSetup) {
                    HStack(spacing: 8) {
                        Image(systemName: gmailIcon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MailTheme.secondaryText)
                            .frame(width: 16)
                        Text(store.gmailConnectionState.sidebarTitle)
                            .font(MailTheme.font(12))
                            .foregroundStyle(MailTheme.secondaryText)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Hairline()
                Button {
                    store.presentCommandPalette()
                } label: {
                    HStack {
                        Text("Command menu")
                            .font(MailTheme.font(12))
                            .foregroundStyle(MailTheme.secondaryText)
                        Spacer()
                        ShortcutChip(text: "⌘ K")
                    }
                    .frame(height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 12)
        .padding(.top, 44)
        .padding(.bottom, 14)
        .frame(width: 236)
        .background(MailTheme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(MailTheme.border).frame(width: 1)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(MailTheme.glassHighlight.opacity(0.55))
                .frame(height: 1)
                .allowsHitTesting(false)
        }
    }

    private var gmailIcon: String {
        switch store.gmailConnectionState {
        case .connected: "checkmark.circle.fill"
        case .connecting, .syncing: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.circle"
        case .disconnected, .readyToConnect: "envelope"
        }
    }
}

private struct SidebarRow: View {
    @Bindable var store: MailStore
    let mailbox: Mailbox
    @State private var isHovering = false

    var body: some View {
        Button {
            store.selectMailbox(mailbox)
        } label: {
            HStack(spacing: 0) {
                Image(systemName: mailbox.icon)
                    .font(.system(size: 12, weight: mailbox == .inbox ? .semibold : .regular))
                    .foregroundStyle(mailbox == .inbox ? MailTheme.text : MailTheme.secondaryText)
                    .frame(width: 16)

                Text(mailbox.rawValue)
                    .font(MailTheme.font(13, weight: store.selectedMailbox == mailbox ? .medium : .regular))
                    .foregroundStyle(MailTheme.text)
                    .padding(.leading, 10)

                Spacer()

                if let count = store.count(for: mailbox), count > 0 {
                    Text("\(count)")
                        .font(MailTheme.font(12))
                        .foregroundStyle(mailbox == .drafts ? MailTheme.faintText : MailTheme.text)
                        .frame(width: 28, alignment: .trailing)
                } else {
                    Color.clear.frame(width: 28, height: 1)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(store.selectedMailbox == mailbox ? MailTheme.activeNavigation : (isHovering ? MailTheme.hoverSurface : .clear))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        store.selectedMailbox == mailbox ? MailTheme.glassBorder.opacity(0.65) : .clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
