import SwiftUI

struct ComposerFormattingButton: View {
    let perform: (MailEditorCommand) -> Void
    var onPresentationChange: ((Bool) -> Void)?
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
            onPresentationChange?(isPresented)
        } label: {
            Text("Aa")
                .font(MailTheme.font(13, weight: .medium))
                .foregroundStyle(MailTheme.secondaryText)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Formatting")
        .accessibilityLabel("Formatting")
        .popover(isPresented: $isPresented, arrowEdge: .leading) {
            VStack(spacing: 2) {
                ForEach(MailEditorCommand.allCases, id: \.rawValue) { command in
                    Button {
                        isPresented = false
                        onPresentationChange?(false)
                        perform(command)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: command.systemImage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(MailTheme.secondaryText)
                                .frame(width: 18)

                            Text(command.title)
                                .font(MailTheme.font(13))
                                .foregroundStyle(MailTheme.text)

                            Spacer()

                            if !command.shortcut.isEmpty {
                                Text(command.shortcut)
                                    .font(MailTheme.font(12))
                                    .foregroundStyle(MailTheme.mutedText)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .frame(width: 224)
        }
        .onChange(of: isPresented) { _, presented in
            onPresentationChange?(presented)
        }
    }
}

struct ComposerLinkEditor: View {
    let request: ComposerLinkRequest
    let onApply: (URL) -> Void
    let onCancel: () -> Void
    @State private var address = ""
    @State private var status = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add link to “\(conciseSelection)”")
                .font(MailTheme.font(13, weight: .medium))
                .foregroundStyle(MailTheme.text)
                .lineLimit(1)

            HStack(spacing: 8) {
                TextField("Paste a web address", text: $address)
                    .textFieldStyle(.plain)
                    .font(MailTheme.font(13))
                    .focused($isFocused)
                    .onSubmit(apply)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MailTheme.border, lineWidth: 1)
                    }

                Button("Apply", action: apply)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(normalizedURL == nil)
            }

            if !status.isEmpty {
                Text(status)
                    .font(MailTheme.font(12))
                    .foregroundStyle(MailTheme.secondaryText)
            }
        }
        .padding(12)
        .frame(width: 360)
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                isFocused = true
            }
        }
        .onExitCommand(perform: onCancel)
    }

    private var conciseSelection: String {
        if request.selectedText.count <= 48 { return request.selectedText }
        return String(request.selectedText.prefix(48)) + "…"
    }

    private var normalizedURL: URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func apply() {
        guard let url = normalizedURL else {
            status = "Enter a valid web address."
            return
        }
        request.apply(url)
        onApply(url)
    }
}

struct ComposerImageSizeEditor: View {
    let request: ComposerImageResizeRequest
    let onSelect: (InlineImageDisplaySize) -> Void
    let onCancel: () -> Void
    @State private var selectedSize: InlineImageDisplaySize

    init(
        request: ComposerImageResizeRequest,
        onSelect: @escaping (InlineImageDisplaySize) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.onSelect = onSelect
        self.onCancel = onCancel
        _selectedSize = State(initialValue: request.size)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Image size")
                .font(MailTheme.font(13, weight: .medium))
                .foregroundStyle(MailTheme.text)

            HStack(spacing: 4) {
                ForEach(InlineImageDisplaySize.allCases) { size in
                    Button {
                        selectedSize = size
                        request.apply(size)
                        onSelect(size)
                    } label: {
                        Text(size.title)
                            .font(MailTheme.font(12, weight: selectedSize == size ? .medium : .regular))
                            .foregroundStyle(MailTheme.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(selectedSize == size ? MailTheme.activeNavigation : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .frame(width: 248)
        .onExitCommand(perform: onCancel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Resize \(request.name)")
    }
}

struct AttachmentDropTarget: ViewModifier {
    let cornerRadius: CGFloat
    let onDrop: ([URL]) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty else { return false }
                onDrop(files)
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            MailTheme.secondaryText.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                        .padding(2)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func acceptsMailAttachments(
        cornerRadius: CGFloat,
        onDrop: @escaping ([URL]) -> Void
    ) -> some View {
        modifier(AttachmentDropTarget(cornerRadius: cornerRadius, onDrop: onDrop))
    }
}
