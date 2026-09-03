import SwiftUI

struct ThreadView: View {
    @Bindable var store: MailStore
    let thread: MailThread
    @State private var expandedMessageID: String?
    @State private var isMoreMenuPresented = false
    @State private var replyComposerHeight: CGFloat = 202
    @State private var isMessageContentReady = false
    @State private var isReplyComposerReady = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: MailStore, thread: MailThread) {
        self.store = store
        self.thread = thread
        _expandedMessageID = State(initialValue: thread.defaultExpandedMessageID)
    }

    var body: some View {
        VStack(spacing: 0) {
            threadHeader

            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView {
                        Group {
                            if thread.messages.count > 12 {
                                LazyVStack(spacing: 10) {
                                    conversationRows(maximumHeight: max(260, viewport.size.height - 40))
                                }
                            } else {
                                VStack(spacing: 10) {
                                    conversationRows(maximumHeight: max(260, viewport.size.height - 40))
                                }
                            }
                        }
                        .frame(maxWidth: 960, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 48)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    .defaultScrollAnchor(store.isReplyComposerPresented ? .bottom : .top)
                    .onChange(of: thread.messages.count) { _, _ in
                        expandedMessageID = thread.defaultExpandedMessageID
                        scrollToOpeningPosition(proxy, animated: false)
                    }
                    .onChange(of: replyComposerHeight) { previousHeight, height in
                        guard store.isReplyComposerPresented,
                              height > previousHeight,
                              height > 202 else { return }
                        DispatchQueue.main.async {
                            proxy.scrollTo("reply-composer", anchor: .bottom)
                        }
                    }
                    .onChange(of: store.replyFocusRequest) { _, _ in
                        guard store.replyFocusThreadID == thread.id else { return }
                        scrollToOpeningPosition(proxy)
                    }
                    .onChange(of: isMessageContentReady) { _, isReady in
                        // The bottom default anchor already places ongoing
                        // conversations at the reply composer. An explicit
                        // scroll here forced a second layout pass on every
                        // ordinary thread open; reader-only threads still need
                        // a targeted scroll to their latest incoming message.
                        guard isReady, !store.isReplyComposerPresented else { return }
                        scrollToOpeningPosition(proxy, animated: false)
                    }
                    .onChange(of: isReplyComposerReady) { _, isReady in
                        // Only an unusually fast explicit Reply request can
                        // arrive before the staged editor is ready. Default-
                        // open composers are already positioned by the anchor.
                        guard isReady,
                              store.replyFocusThreadID == thread.id else { return }
                        scrollToOpeningPosition(proxy, animated: false)
                    }
                }
            }
        }
        .background(MailTheme.structureSurface)
        .onAppear {
            if expandedMessageID == nil { expandedMessageID = thread.defaultExpandedMessageID }
        }
        .onChange(of: thread.id) { _, _ in
            expandedMessageID = thread.defaultExpandedMessageID
            replyComposerHeight = 202
        }
        .task(id: thread.id) {
            // Commit the header, messages, reply chrome, and native editor on
            // separate frames. This keeps cached opens visually immediate while
            // preventing one oversized AppKit/SwiftUI layout transaction.
            isMessageContentReady = false
            isReplyComposerReady = false
            do {
                try await Task.sleep(for: .milliseconds(40))
                guard !Task.isCancelled else { return }
                isMessageContentReady = true
                try await Task.sleep(for: .milliseconds(40))
                guard !Task.isCancelled else { return }
                isReplyComposerReady = true
            } catch {
                return
            }
        }
    }

    @ViewBuilder
    private func conversationRows(maximumHeight: CGFloat) -> some View {
        if isMessageContentReady {
            if thread.messages.isEmpty {
                ThreadBodyLoadingView(error: store.threadBodyLoadErrors[thread.id]) {
                    store.retryLoadingThreadBody(thread.id)
                }
            } else {
                ForEach(thread.messages) { message in
                    if expandedMessageID == message.id {
                        ExpandedMessageView(
                            message: message,
                            threadEmail: thread.email,
                            subject: thread.subject
                        )
                    } else {
                        CollapsedMessageView(message: message) {
                            expand(message.id)
                        }
                    }
                }
            }
        }

        if isReplyComposerReady,
           store.isReplyComposerPresented,
           !thread.messages.isEmpty {
            ReplyComposerView(
                store: store,
                recipient: thread.sender,
                focusRequest: store.replyFocusThreadID == thread.id
                    ? store.replyFocusRequest
                    : 0,
                height: $replyComposerHeight,
                maximumHeight: maximumHeight
            )
            .id("reply-composer")
        }
    }

    private func scrollToOpeningPosition(
        _ proxy: ScrollViewProxy,
        animated: Bool = true
    ) {
        DispatchQueue.main.async {
            let scroll = {
                if store.isReplyComposerPresented {
                    guard isReplyComposerReady else { return }
                    proxy.scrollTo("reply-composer", anchor: .bottom)
                } else {
                    guard isMessageContentReady,
                          let messageID = expandedMessageID else { return }
                    proxy.scrollTo(messageID, anchor: .top)
                }
            }

            if animated, !reduceMotion {
                withAnimation(.snappy(duration: 0.12, extraBounce: 0), scroll)
            } else {
                scroll()
            }
        }
    }

    private func expand(_ messageID: String) {
        guard expandedMessageID != messageID else { return }
        if reduceMotion {
            expandedMessageID = messageID
        } else {
            withAnimation(.snappy(duration: 0.16, extraBounce: 0)) {
                expandedMessageID = messageID
            }
        }
    }

    private var threadHeader: some View {
        HStack(spacing: 12) {
            Button {
                store.closeThread()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MailTheme.secondaryText)
                    .frame(width: 24, height: 32)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(thread.subject)
                    .font(MailTheme.font(14, weight: .medium))
                    .foregroundStyle(MailTheme.text)
                    .lineLimit(1)
                Text("\(thread.sender) · \(thread.email)")
                    .font(MailTheme.font(12))
                    .foregroundStyle(MailTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            Button {
                store.requestReply()
            } label: {
                HStack(spacing: 8) {
                    Text("Reply")
                    Text("R").foregroundStyle(MailTheme.mutedText)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .help("Reply (R)")

            Button {
                store.archiveCurrent()
            } label: {
                HStack(spacing: 8) {
                    Text("Archive")
                    Text("E").foregroundStyle(MailTheme.mutedText)
                }
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                isMoreMenuPresented.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text("More")
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .popover(isPresented: $isMoreMenuPresented, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    MoreActionButton(
                        title: thread.isStarred ? "Unstar" : "Star",
                        systemImage: thread.isStarred ? "star.slash" : "star",
                        action: {
                            store.toggleStar()
                            isMoreMenuPresented = false
                        }
                    )
                    MoreActionButton(
                        title: thread.isUnread ? "Mark Read" : "Mark Unread",
                        systemImage: thread.isUnread ? "envelope.open" : "envelope.badge",
                        action: {
                            store.toggleUnread()
                            isMoreMenuPresented = false
                        }
                    )
                }
                .padding(8)
                .frame(width: 180)
                .background(MailTheme.modalSurface)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 76)
        .background(Color.white.opacity(0.04))
        .overlay(alignment: .bottom) { Hairline() }
    }
}

private struct ThreadBodyLoadingView: View {
    let error: String?
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let error {
                Text("This message could not load")
                    .font(MailTheme.font(13, weight: .medium))
                    .foregroundStyle(MailTheme.text)
                Text(error)
                    .font(MailTheme.font(12))
                    .foregroundStyle(MailTheme.mutedText)
                    .multilineTextAlignment(.center)
                Button("Try Again", action: retry)
                    .buttonStyle(SecondaryButtonStyle())
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Loading message…")
                    .font(MailTheme.font(12))
                    .foregroundStyle(MailTheme.mutedText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(MailTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MailTheme.glassBorder.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: MailTheme.darkControl.opacity(0.07), radius: 12, x: 0, y: 6)
    }
}

private struct MoreActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(MailTheme.font(13))
                .foregroundStyle(MailTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CollapsedMessageView: View {
    let message: MailMessage
    let onOpen: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Text(message.sender)
                .font(MailTheme.font(13, weight: .medium))
                .foregroundStyle(MailTheme.text)
                .frame(width: 140, alignment: .leading)

            Text(message.compactPreview)
                .font(MailTheme.font(13))
                .foregroundStyle(MailTheme.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(message.timestamp)
                .font(MailTheme.font(12))
                .foregroundStyle(MailTheme.mutedText)
                .frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(isHovering ? MailTheme.controlSurface : MailTheme.messageSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isHovering ? MailTheme.glassBorder.opacity(0.58) : MailTheme.border,
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open message from \(message.sender), \(message.timestamp)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onOpen()
        }
        .onHover { isHovering = $0 }
    }
}

private struct ExpandedMessageView: View {
    let message: MailMessage
    let threadEmail: String
    let subject: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.sender)
                        .font(MailTheme.font(13, weight: .medium))
                        .foregroundStyle(MailTheme.text)

                    Text(message.sender == "You" ? "From me" : "From \(threadEmail)")
                        .font(MailTheme.font(12))
                        .foregroundStyle(MailTheme.mutedText)

                    Text(message.recipientLine)
                        .font(MailTheme.font(12))
                        .foregroundStyle(MailTheme.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.timestamp)
                        .font(MailTheme.font(12))
                        .foregroundStyle(MailTheme.mutedText)
                    Text(subject)
                        .font(MailTheme.font(12))
                        .foregroundStyle(MailTheme.secondaryText)
                        .lineLimit(1)
                }
            }

            Group {
                if let htmlBody = message.htmlBody,
                   !htmlBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MailHTMLBodyView(html: htmlBody)
                } else {
                    InlineMessageBodyView(
                        // GmailMessageParser normalizes quoted history and line
                        // wrapping before persistence. Rendering the stored body
                        // directly avoids repeating that parse during layout.
                        body: message.body,
                        images: message.inlineImages
                    )
                }
            }
            .frame(maxWidth: 720, alignment: .leading)

            if !message.attachmentNames.isEmpty {
                MessageAttachmentStrip(names: message.attachmentNames)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(MailTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MailTheme.glassBorder.opacity(0.74), lineWidth: 1)
        }
        .shadow(color: MailTheme.darkControl.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}

private struct ReplyComposerView: View {
    @Bindable var store: MailStore
    let recipient: String
    let focusRequest: Int
    @Binding var height: CGFloat
    let maximumHeight: CGFloat
    @State private var isChoosingImagePlacement = false
    @State private var pendingImageURLs: [URL] = []
    @State private var linkRequest: ComposerLinkRequest?
    @State private var imageResizeRequest: ComposerImageResizeRequest?
    @State private var editorContentHeight: CGFloat = 0
    @State private var isEditorReady = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Reply to \(recipient)")
                    .font(MailTheme.font(12))
                    .foregroundStyle(MailTheme.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 42)

            Hairline()

            ZStack(alignment: .topLeading) {
                if store.replyDraft.isEmpty {
                    Text("Write a reply…")
                        .font(MailTheme.font(14))
                        .foregroundStyle(MailTheme.faintText)
                        .padding(.leading, 16)
                        .padding(.top, 13)
                        .allowsHitTesting(false)
                }

                if isEditorReady {
                    MailTextEditor(
                        text: $store.replyDraft,
                        inlineImages: $store.replyInlineImages,
                        focusRequest: focusRequest,
                        formattingRequest: store.replyFormattingRequest,
                        inlineImageRequest: store.replyInlineImageRequest,
                        accessibilityLabel: "Reply to \(recipient)",
                        focusNotification: .focusReplyEditor,
                        onAttachFiles: presentAttachmentPicker,
                        onContentHeightChange: { contentHeight in
                            editorContentHeight = contentHeight
                            updateHeight()
                        },
                        onLinkRequested: { request in
                            linkRequest = request
                            store.isComposerOverlayPresented = true
                        },
                        onImageResizeRequested: { request in
                            imageResizeRequest = request
                            store.isComposerOverlayPresented = true
                        }
                    )
                }
            }
            .frame(maxHeight: .infinity)
            .popover(
                item: $linkRequest,
                attachmentAnchor: .rect(.rect(linkRequest?.anchorRect ?? CGRect(x: 16, y: 16, width: 2, height: 18))),
                arrowEdge: .top
            ) { request in
                ComposerLinkEditor(request: request) { _ in
                    linkRequest = nil
                    store.isComposerOverlayPresented = false
                    store.showToast("Link added")
                } onCancel: {
                    linkRequest = nil
                    store.isComposerOverlayPresented = false
                }
            }
            .popover(
                item: $imageResizeRequest,
                attachmentAnchor: .rect(.rect(imageResizeRequest?.anchorRect ?? CGRect(x: 16, y: 16, width: 2, height: 18))),
                arrowEdge: .top
            ) { request in
                ComposerImageSizeEditor(request: request) { _ in
                    imageResizeRequest = nil
                    store.isComposerOverlayPresented = false
                } onCancel: {
                    imageResizeRequest = nil
                    store.isComposerOverlayPresented = false
                }
            }

            if !store.replyAttachments.isEmpty {
                AttachmentStrip(attachments: store.replyAttachments) { attachment in
                    store.removeReplyAttachment(attachment)
                }
            }

            HStack(spacing: 14) {
                Button(action: presentAttachmentPicker) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 12))
                        .foregroundStyle(MailTheme.secondaryText)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .help("Attach files (⇧⌘A)")

                ComposerFormattingButton(
                    perform: { command in store.formatReply(command) },
                    onPresentationChange: { store.isComposerOverlayPresented = $0 }
                )

                Text("Draft saved automatically")
                    .font(MailTheme.font(12))
                    .foregroundStyle(MailTheme.mutedText)

                Spacer()

                HStack(spacing: 6) {
                    ShortcutChip(text: "⌘ ↵")
                    Text("Send")
                        .font(MailTheme.font(12))
                        .foregroundStyle(MailTheme.mutedText)
                }

                Button("Send") {
                    store.sendReply()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.5)
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(height: 44)
        }
        .frame(height: height)
        .background(MailTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MailTheme.glassBorder.opacity(0.74), lineWidth: 1)
        }
        .shadow(color: MailTheme.darkControl.opacity(0.09), radius: 14, x: 0, y: 7)
        .acceptsMailAttachments(cornerRadius: 16) { urls in
            handleSelectedFiles(urls)
        }
        .confirmationDialog(
            pendingImageURLs.count == 1 ? "Add photo" : "Add photos",
            isPresented: $isChoosingImagePlacement,
            titleVisibility: .visible
        ) {
            Button("Attach as file") {
                store.addReplyAttachments(pendingImageURLs)
                pendingImageURLs = []
                store.isComposerOverlayPresented = false
            }
            .keyboardShortcut(.defaultAction)

            Button("Embed in body") {
                store.embedReplyImages(pendingImageURLs)
                pendingImageURLs = []
                store.isComposerOverlayPresented = false
            }

            Button("Cancel", role: .cancel) {
                pendingImageURLs = []
                store.isComposerOverlayPresented = false
            }
        } message: {
            Text("Choose how this image should appear. It will attach as a file by default.")
        }
        .onChange(of: isChoosingImagePlacement) { _, isPresented in
            if !isPresented { store.isComposerOverlayPresented = false }
        }
        .onChange(of: imageResizeRequest?.id) { _, requestID in
            if requestID == nil { store.isComposerOverlayPresented = false }
        }
        .onAppear(perform: updateHeight)
        .onChange(of: store.replyAttachments.count) { _, _ in updateHeight() }
        .onChange(of: maximumHeight) { _, _ in updateHeight() }
        .task {
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            isEditorReady = true
        }
    }

    private var canSend: Bool {
        !store.replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !store.replyAttachments.isEmpty
            || !store.replyInlineImages.isEmpty
    }

    private func handleSelectedFiles(_ urls: [URL]) {
        let imageURLs = urls.filter(InlineDraftImage.isSupportedImage)
        let regularFiles = urls.filter { !InlineDraftImage.isSupportedImage($0) }
        if !regularFiles.isEmpty {
            store.addReplyAttachments(regularFiles)
        }
        guard !imageURLs.isEmpty else { return }
        pendingImageURLs = imageURLs
        store.isComposerOverlayPresented = true
        isChoosingImagePlacement = true
    }

    private func presentAttachmentPicker() {
        store.isComposerOverlayPresented = true
        AttachmentPickerController.shared.present { urls in
            store.isComposerOverlayPresented = false
            guard !urls.isEmpty else { return }
            handleSelectedFiles(urls)
        }
    }

    private func updateHeight() {
        let attachmentHeight: CGFloat = store.replyAttachments.isEmpty ? 0 : 36
        let chromeHeight: CGFloat = 42 + 1 + 44 + attachmentHeight
        let desired = min(maximumHeight, max(202, ceil(editorContentHeight + chromeHeight)))
        guard abs(height - desired) > 0.5 else { return }
        height = desired
    }
}
