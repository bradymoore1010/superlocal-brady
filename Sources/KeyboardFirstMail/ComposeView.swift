import SwiftUI

struct ComposeView: View {
    @Bindable var store: MailStore
    @FocusState private var focusedField: Field?
    @State private var isChoosingImagePlacement = false
    @State private var pendingImageURLs: [URL] = []
    @State private var linkRequest: ComposerLinkRequest?
    @State private var imageResizeRequest: ComposerImageResizeRequest?

    private enum Field {
        case to
        case subject
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New message")
                    .font(MailTheme.font(14, weight: .medium))
                    .foregroundStyle(MailTheme.text)
                Spacer()
                Button {
                    store.closeCompose()
                } label: {
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

            recipientField
                .zIndex(2)
            Hairline().padding(.horizontal, 16)
            fieldRow(label: "Subject", text: $store.composeSubject, field: .subject)
            Hairline()

            ZStack(alignment: .topLeading) {
                if store.composeBody.isEmpty {
                    Text("Write your message…")
                        .font(MailTheme.font(14))
                        .foregroundStyle(MailTheme.faintText)
                        .padding(.leading, 16)
                        .padding(.top, 13)
                        .allowsHitTesting(false)
                }

                MailTextEditor(
                    text: $store.composeBody,
                    inlineImages: $store.composeInlineImages,
                    formattingRequest: store.composeFormattingRequest,
                    inlineImageRequest: store.composeInlineImageRequest,
                    accessibilityLabel: "Message body",
                    onAttachFiles: presentAttachmentPicker,
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

            if !store.composeAttachments.isEmpty {
                AttachmentStrip(attachments: store.composeAttachments) { attachment in
                    store.removeComposeAttachment(attachment)
                }
            }

            HStack(spacing: 10) {
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
                    perform: { command in store.formatCompose(command) },
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
                Button("Send") { store.sendCompose() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.5)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
        }
        .frame(width: 640, height: 500)
        .floatingGlassSurface(cornerRadius: 18)
        .acceptsMailAttachments(cornerRadius: 18) { urls in
            handleSelectedFiles(urls)
        }
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                focusedField = .to
            }
        }
        .confirmationDialog(
            pendingImageURLs.count == 1 ? "Add photo" : "Add photos",
            isPresented: $isChoosingImagePlacement,
            titleVisibility: .visible
        ) {
            Button("Attach as file") {
                store.addComposeAttachments(pendingImageURLs)
                pendingImageURLs = []
                store.isComposerOverlayPresented = false
            }
            .keyboardShortcut(.defaultAction)

            Button("Embed in body") {
                store.embedComposeImages(pendingImageURLs)
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
    }

    private func fieldRow(label: String, text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(MailTheme.font(13))
                .foregroundStyle(MailTheme.mutedText)
                .frame(width: 54, alignment: .leading)
            TextField(label == "To" ? "name@example.com" : "Message subject", text: text)
                .textFieldStyle(.plain)
                .font(MailTheme.font(13))
                .foregroundStyle(MailTheme.text)
                .focused($focusedField, equals: field)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var recipientField: some View {
        HStack(spacing: 12) {
            Text("To")
                .font(MailTheme.font(13))
                .foregroundStyle(MailTheme.mutedText)
                .frame(width: 54, alignment: .leading)

            TextField("name@example.com", text: $store.composeTo)
                .textFieldStyle(.plain)
                .font(MailTheme.font(13))
                .foregroundStyle(MailTheme.text)
                .focused($focusedField, equals: .to)
                .onKeyPress(.tab) {
                    store.acceptComposeRecipientSuggestion() ? .handled : .ignored
                }
                .onKeyPress(.downArrow) {
                    guard !store.composeRecipientSuggestions.isEmpty else { return .ignored }
                    store.moveComposeRecipientSelection(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard !store.composeRecipientSuggestions.isEmpty else { return .ignored }
                    store.moveComposeRecipientSelection(-1)
                    return .handled
                }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .overlay(alignment: .topLeading) {
            if focusedField == .to, !store.composeRecipientSuggestions.isEmpty {
                RecipientSuggestionMenu(
                    suggestions: store.composeRecipientSuggestions,
                    selectedIndex: store.selectedComposeRecipientSuggestionIndex
                ) { suggestion in
                    _ = store.acceptComposeRecipientSuggestion(suggestion)
                    focusedField = .to
                }
                .frame(width: 526)
                .offset(x: 82, y: 40)
            }
        }
    }

    private var canSend: Bool {
        !store.composeTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !store.composeSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!store.composeBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !store.composeAttachments.isEmpty
                || !store.composeInlineImages.isEmpty)
    }

    private func handleSelectedFiles(_ urls: [URL]) {
        let imageURLs = urls.filter(InlineDraftImage.isSupportedImage)
        let regularFiles = urls.filter { !InlineDraftImage.isSupportedImage($0) }
        if !regularFiles.isEmpty {
            store.addComposeAttachments(regularFiles)
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
}

private struct RecipientSuggestionMenu: View {
    let suggestions: [RecipientSuggestion]
    let selectedIndex: Int
    let onSelect: (RecipientSuggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    onSelect(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        Text(initials(for: suggestion))
                            .font(MailTheme.font(11, weight: .medium))
                            .foregroundStyle(MailTheme.secondaryText)
                            .frame(width: 26, height: 26)
                            .background(MailTheme.secondarySurface)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion.name.isEmpty ? suggestion.email : suggestion.name)
                                .font(MailTheme.font(13, weight: .medium))
                                .foregroundStyle(MailTheme.text)
                                .lineLimit(1)
                            if !suggestion.name.isEmpty {
                                Text(suggestion.email)
                                    .font(MailTheme.font(12))
                                    .foregroundStyle(MailTheme.mutedText)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 12)

                        if index == selectedIndex {
                            HStack(spacing: 5) {
                                ShortcutChip(text: "Tab")
                                Text("Complete")
                                    .font(MailTheme.font(12))
                                    .foregroundStyle(MailTheme.mutedText)
                            }
                        } else if suggestion.wasPreviouslyEmailed {
                            Text("Previously emailed")
                                .font(MailTheme.font(12))
                                .foregroundStyle(MailTheme.mutedText)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 46)
                    .background(index == selectedIndex ? MailTheme.activeNavigation : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(MailTheme.modalSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MailTheme.glassBorder, lineWidth: 1)
        }
        .shadow(color: MailTheme.darkControl.opacity(0.22), radius: 22, x: 0, y: 12)
    }

    private func initials(for suggestion: RecipientSuggestion) -> String {
        let source = suggestion.name.isEmpty
            ? String(suggestion.email.split(separator: "@").first ?? "")
            : suggestion.name
        let words = source.split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "_" })
        let letters = words.prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }
}
