import SwiftUI

struct GmailConnectionView: View {
    @Bindable var store: MailStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(MailTheme.font(14, weight: .medium))
                    .foregroundStyle(MailTheme.text)
                Spacer()
                Button(action: store.closeGmailSetup) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MailTheme.secondaryText)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            Hairline()

            VStack(alignment: .leading, spacing: 18) {
                statusContent
                actionButtons
                HStack {
                    Spacer()
                    Link("Privacy", destination: URL(string: "https://mooreunderscore.com/mail/privacy")!)
                        .font(MailTheme.font(11))
                        .foregroundStyle(MailTheme.secondaryText)
                }
            }
            .padding(20)
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .floatingGlassSurface(cornerRadius: 18)
    }

    private var title: String {
        if store.gmailConnectionState.isConnected { return "Gmail connected" }
        return "Connect Gmail"
    }

    @ViewBuilder
    private var statusContent: some View {
        switch store.gmailConnectionState {
        case .disconnected:
            message(
                "Use a Google Desktop OAuth credential to connect this Mac directly to Gmail. Your refresh token stays in Keychain."
            )
        case .readyToConnect:
            VStack(alignment: .leading, spacing: 8) {
                Label("OAuth credentials ready", systemImage: "checkmark.circle.fill")
                    .font(MailTheme.font(13, weight: .medium))
                    .foregroundStyle(MailTheme.text)
                message("Continue to Google to approve read, send, archive, star, and read-state access.")
            }
        case .connecting:
            progressRow(title: "Waiting for Google authorization…", detail: "Complete the approval in your browser.")
        case let .syncing(completed, total):
            progressRow(
                title: total > 0 ? "Syncing \(completed) of \(total) conversations…" : "Starting Gmail sync…",
                detail: "Cached mail appears immediately on future launches."
            )
        case let .connected(email, syncedAt):
            VStack(alignment: .leading, spacing: 8) {
                Label(email, systemImage: "checkmark.circle.fill")
                    .font(MailTheme.font(13, weight: .medium))
                    .foregroundStyle(MailTheme.text)
                message(syncDescription(syncedAt))
                if let directoryStatus = store.gmailRecipientDirectoryStatus {
                    message(directoryStatus)
                }
            }
        case let .failed(messageText):
            VStack(alignment: .leading, spacing: 8) {
                Label("Gmail needs attention", systemImage: "exclamationmark.circle")
                    .font(MailTheme.font(13, weight: .medium))
                    .foregroundStyle(MailTheme.text)
                message(messageText)
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch store.gmailConnectionState {
        case .disconnected:
            VStack(spacing: 10) {
                Button("Choose OAuth JSON…", action: store.chooseGmailConfiguration)
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Button("Open Google Cloud setup", action: store.openGoogleCloudSetup)
                    .buttonStyle(.plain)
                    .font(MailTheme.font(12))
                    .foregroundStyle(MailTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        case .readyToConnect:
            HStack {
                Button("Replace OAuth JSON…", action: store.chooseGmailConfiguration)
                    .buttonStyle(.plain)
                    .font(MailTheme.font(12))
                    .foregroundStyle(MailTheme.secondaryText)
                Spacer()
                Button("Connect Gmail", action: store.connectGmail)
                    .buttonStyle(PrimaryButtonStyle())
            }
        case .connecting, .syncing:
            EmptyView()
        case .connected:
            HStack {
                Button("Reconnect", action: store.connectGmail)
                    .buttonStyle(.plain)
                    .font(MailTheme.font(12))
                    .foregroundStyle(MailTheme.secondaryText)
                Spacer()
                Button("Sync now", action: store.syncGmail)
                    .buttonStyle(SecondaryButtonStyle())
                Button("Done", action: store.closeGmailSetup)
                    .buttonStyle(PrimaryButtonStyle())
            }
        case .failed:
            HStack {
                Button("Choose OAuth JSON…", action: store.chooseGmailConfiguration)
                    .buttonStyle(.plain)
                    .font(MailTheme.font(12))
                    .foregroundStyle(MailTheme.secondaryText)
                Spacer()
                Button(store.gmailHasConfiguration ? "Try again" : "Open setup", action: retry)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(MailTheme.font(13))
            .foregroundStyle(MailTheme.secondaryText)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func progressRow(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView().controlSize(.small).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(MailTheme.font(13, weight: .medium))
                    .foregroundStyle(MailTheme.text)
                message(detail)
            }
        }
    }

    private func retry() {
        if store.gmailHasConfiguration { store.connectGmail() }
        else { store.openGoogleCloudSetup() }
    }

    private func syncDescription(_ date: Date?) -> String {
        guard let date else { return "Connected and ready to sync." }
        return "Last synced \(date.formatted(date: .abbreviated, time: .shortened))."
    }
}
