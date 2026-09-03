import SwiftUI

struct CommandPaletteView: View {
    @Bindable var store: MailStore
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            switch store.commandPaletteMode {
            case .commands:
                commandList
            case .signatures:
                SignatureSettingsView(store: store)
            case .scheduleSend:
                ScheduleSendView(store: store)
            case .reminder:
                ReminderPickerView(store: store)
            }
        }
        .padding(10)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .floatingGlassSurface(cornerRadius: 18)
        .onChange(of: store.commandQuery) { _, query in
            store.clampCommandSelection()
            store.searchGmailIfNeeded(query)
        }
    }

    private var commandList: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(MailTheme.mutedText)
                    .frame(width: 20)

                TextField("Search mail or run a command…", text: $store.commandQuery)
                    .textFieldStyle(.plain)
                    .font(MailTheme.font(14))
                    .foregroundStyle(MailTheme.text)
                    .focused($isFocused)
                    .onSubmit { store.executeSelectedCommand() }
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .overlay(alignment: .bottom) { Hairline() }

            Group {
                if store.paletteResultCount == 0 {
                    VStack(spacing: 6) {
                        Text("No command or mail found")
                            .font(MailTheme.font(13, weight: .medium))
                            .foregroundStyle(MailTheme.text)
                        Text("Try an action, sender, subject, or search filter.")
                            .font(MailTheme.font(12))
                            .foregroundStyle(MailTheme.mutedText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            if !store.filteredCommands.isEmpty {
                                Section {
                                    ForEach(Array(store.filteredCommands.enumerated()), id: \.element.id) { index, command in
                                        CommandRow(
                                            command: command,
                                            isSelected: index == store.selectedCommandIndex
                                        ) {
                                            store.selectedCommandIndex = index
                                            store.perform(command.action)
                                        } onHover: {
                                            store.selectedCommandIndex = index
                                        }
                                    }
                                } header: {
                                    PaletteSectionHeader(title: "Actions")
                                }
                            }

                            if !store.paletteMailResults.isEmpty {
                                Section {
                                    ForEach(Array(store.paletteMailResults.enumerated()), id: \.element.id) { index, thread in
                                        let paletteIndex = store.filteredCommands.count + index
                                        MailPaletteRow(
                                            thread: thread,
                                            isSelected: paletteIndex == store.selectedCommandIndex
                                        ) {
                                            store.selectedCommandIndex = paletteIndex
                                            store.openFromCommandPalette(thread)
                                        } onHover: {
                                            store.selectedCommandIndex = paletteIndex
                                        }
                                    }
                                } header: {
                                    PaletteSectionHeader(title: "Mail")
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .frame(height: 360)

            Hairline().padding(.horizontal, 4).padding(.top, 4)

            HStack {
                HStack(spacing: 12) {
                    paletteHint(keys: ["↑", "↓"], label: "Select")
                    paletteHint(keys: ["↵"], label: "Run")
                }
                Spacer()
                paletteHint(keys: ["Esc"], label: "Close")
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
        }
        .onAppear {
            isFocused = true
        }
    }

    private func paletteHint(keys: [String], label: String) -> some View {
        HStack(spacing: 5) {
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { ShortcutChip(text: $0) }
            }
            Text(label)
                .font(MailTheme.font(12))
                .foregroundStyle(MailTheme.mutedText)
        }
    }

}

private struct PaletteSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(MailTheme.font(12))
            .foregroundStyle(MailTheme.mutedText)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .bottomLeading)
            .padding(.horizontal, 8)
            .background(MailTheme.modalSurface)
    }
}

private struct CommandRow: View {
    let command: MailCommand
    let isSelected: Bool
    let action: () -> Void
    let onHover: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: command.icon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isSelected ? MailTheme.inkOnDark.opacity(0.82) : MailTheme.secondaryText)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(command.title)
                        .font(MailTheme.font(13, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? MailTheme.inkOnDark : MailTheme.text)
                        .lineLimit(1)

                    if isSelected, let subtitle = command.subtitle {
                        Text(subtitle)
                            .font(MailTheme.font(12))
                            .foregroundStyle(isSelected ? MailTheme.inkOnDark.opacity(0.70) : MailTheme.secondaryText)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 8)

                Spacer()

                if !command.shortcut.isEmpty {
                    ShortcutChip(text: command.shortcut, dark: isSelected)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(isSelected ? MailTheme.darkControl : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { onHover() }
        }
    }
}

private struct MailPaletteRow: View {
    let thread: MailThread
    let isSelected: Bool
    let action: () -> Void
    let onHover: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: thread.hasAttachment ? "paperclip" : "envelope")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(isSelected ? MailTheme.inkOnDark.opacity(0.82) : MailTheme.secondaryText)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(thread.sender)
                            .font(MailTheme.font(13, weight: .medium))
                            .foregroundStyle(isSelected ? MailTheme.inkOnDark : MailTheme.text)
                            .lineLimit(1)

                        Text(thread.subject)
                            .font(MailTheme.font(13))
                            .foregroundStyle(isSelected ? MailTheme.inkOnDark.opacity(0.72) : MailTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Text(thread.displayPreview)
                        .font(MailTheme.font(12))
                        .foregroundStyle(isSelected ? MailTheme.inkOnDark.opacity(0.66) : MailTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Text(thread.displayDate)
                    .font(MailTheme.font(12))
                    .foregroundStyle(isSelected ? MailTheme.inkOnDark.opacity(0.66) : MailTheme.mutedText)
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .background(isSelected ? MailTheme.darkControl : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { onHover() }
        }
    }
}
