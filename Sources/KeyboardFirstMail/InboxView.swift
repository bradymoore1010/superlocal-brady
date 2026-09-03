import SwiftUI

struct InboxView: View {
    @Bindable var store: MailStore
    // One screen plus a small look-ahead is enough for instant scrolling. The
    // next page is appended as its last row approaches the viewport.
    @State private var renderedThreadLimit = 6
    @State private var keyboardScrollAnchorIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            inboxHeader

            ZStack {
                messageList
                    .opacity(store.visibleThreads.isEmpty ? 0 : 1)
                    .allowsHitTesting(!store.visibleThreads.isEmpty)

                if store.visibleThreads.isEmpty {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            KeyboardFooter()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 48)
        .background(MailTheme.structureSurface)
        .onChange(of: store.searchText) { _, _ in
            renderedThreadLimit = 6
            keyboardScrollAnchorIndex = 0
            store.searchGmailIfNeeded(store.searchText)
        }
        .onChange(of: store.selectedMailbox) { _, _ in
            renderedThreadLimit = 6
            keyboardScrollAnchorIndex = 0
        }
    }

    private var inboxHeader: some View {
        HStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(store.selectedMailbox.rawValue)
                    .font(MailTheme.font(24, weight: .medium))
                    .tracking(-0.3)
                    .foregroundStyle(MailTheme.text)

                Text(headerCount)
                    .font(MailTheme.font(12))
                    .foregroundStyle(MailTheme.mutedText)
            }

            Spacer(minLength: 16)

            Button {
                store.presentCompose()
            } label: {
                HStack(spacing: 8) {
                    Text("Draft")
                    Text("C").foregroundStyle(Color.white.opacity(0.72))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .frame(height: 76)
        .background(Color.white.opacity(0.04))
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var headerCount: String {
        if !store.searchText.isEmpty {
            return "\(store.visibleThreads.count) result\(store.visibleThreads.count == 1 ? "" : "s")"
        }
        if store.selectedMailbox == .inbox { return "\(store.unreadCount) unread" }
        return "\(store.visibleThreads.count) conversation\(store.visibleThreads.count == 1 ? "" : "s")"
    }

    private var messageList: some View {
        // Key rows by their stable visual slot. Search often replaces every
        // result ID at once; retaining the row hierarchy avoids destroying and
        // recreating a screen of native controls on each keystroke.
        let renderedThreads = Array(store.visibleThreads.prefix(renderedThreadLimit).enumerated())
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(renderedThreads, id: \.offset) { index, thread in
                        MessageRow(
                            thread: thread,
                            isSelected: store.selectedThreadID == thread.id
                        ) {
                            // A clicked row is already visible; record it as the
                            // scroll anchor so opening it never recenters the list.
                            keyboardScrollAnchorIndex = index
                            store.open(thread)
                        }
                        .id(index)
                        .onAppear {
                            guard index == renderedThreads.last?.offset,
                                  renderedThreadLimit < store.visibleThreads.count else { return }
                            renderedThreadLimit = min(renderedThreadLimit + 6, store.visibleThreads.count)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: store.selectedThreadID) { _, id in
                guard let id,
                      let index = store.visibleThreadIndex(for: id) else { return }
                let needsPage = index >= renderedThreadLimit
                guard needsPage || abs(index - keyboardScrollAnchorIndex) >= 5 else { return }
                if index >= renderedThreadLimit {
                    renderedThreadLimit = min(index + 12, store.visibleThreads.count)
                }
                keyboardScrollAnchorIndex = index
                DispatchQueue.main.async {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(store.searchText.isEmpty ? "Nothing here" : "No mail found")
                .font(MailTheme.font(14, weight: .medium))
                .foregroundStyle(MailTheme.text)
            Text(store.searchText.isEmpty ? "This mailbox is clear." : "Try fewer words or a different filter.")
                .font(MailTheme.font(13))
                .foregroundStyle(MailTheme.mutedText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MessageRow: View {
    let thread: MailThread
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(thread.isUnread ? MailTheme.text : .clear)
                        .frame(width: 6, height: 6)

                    Text(thread.sender)
                        .font(MailTheme.font(13, weight: thread.isUnread ? .medium : .regular))
                        .foregroundStyle(MailTheme.text)
                        .lineLimit(1)
                }
                .frame(width: 190, alignment: .leading)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(thread.subject)
                        .font(MailTheme.font(13, weight: thread.isUnread ? .medium : .regular))
                        .foregroundStyle(MailTheme.text)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Text(thread.displayPreview)
                        .font(MailTheme.font(13))
                        .foregroundStyle(MailTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()

                Text(thread.displayDate)
                    .font(MailTheme.font(12))
                    .foregroundStyle(MailTheme.mutedText)
                    .frame(width: 64, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .frame(height: 64)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(
                    cornerRadius: isSelected || isHovering ? 11 : 0,
                    style: .continuous
                )
                .fill(
                    isSelected
                        ? MailTheme.selectedSurface
                        : (isHovering ? MailTheme.structureBrightSurface : .clear)
                )
            }
            .overlay(alignment: .bottom) {
                if !isSelected && !isHovering { Hairline() }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        isSelected
                            ? MailTheme.glassBorder.opacity(0.62)
                            : (isHovering ? MailTheme.glassBorder.opacity(0.35) : .clear),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct KeyboardFooter: View {
    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            hint(keys: ["J", "K"], label: "Move")
            hint(keys: ["↵"], label: "Open")
            hint(keys: ["E"], label: "Archive")
            hint(keys: ["R"], label: "Reply")
            Spacer()
        }
        .frame(height: 44)
        .overlay(alignment: .top) { Hairline() }
    }

    private func hint(keys: [String], label: String) -> some View {
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
