import AppKit
import SwiftUI

struct SignatureSettingsView: View {
    @Bindable var store: MailStore
    @State private var signatureName = "Default"
    @State private var signature = NSAttributedString(string: "")
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var editorRequest: SignatureEditorRequest?
    @State private var isLinkEditorPresented = false
    @State private var linkText = ""
    @State private var linkURL = ""
    @State private var status = ""

    var body: some View {
        VStack(spacing: 0) {
            PaletteSettingsHeader(title: "Set signatures") {
                store.commandPaletteMode = .commands
            } onClose: {
                store.closeCommandPalette()
            }

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Signature name")
                        .font(MailTheme.font(12))
                        .foregroundStyle(MailTheme.secondaryText)
                    TextField("Default", text: $signatureName)
                        .textFieldStyle(.plain)
                        .font(MailTheme.font(14))
                        .foregroundStyle(MailTheme.text)
                        .padding(.horizontal, 11)
                        .frame(height: 44)
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(MailTheme.border, lineWidth: 1)
                        }
                }

                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        signatureFormatButton("B", weight: .bold) {
                            editorRequest = SignatureEditorRequest(command: .bold)
                        }
                        signatureFormatButton("I", italic: true) {
                            editorRequest = SignatureEditorRequest(command: .italic)
                        }
                        Button("Insert link") {
                            prepareLinkEditor()
                        }
                        .buttonStyle(.plain)
                        .font(MailTheme.font(12, weight: .medium))
                        .foregroundStyle(MailTheme.text)
                        .padding(.horizontal, 10)
                        .frame(height: 32)

                        Spacer()
                    }
                    .padding(5)
                    .frame(height: 44)
                    .overlay {
                        UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10)
                            .stroke(MailTheme.border, lineWidth: 1)
                    }

                    RichSignatureEditor(
                        attributedText: $signature,
                        request: editorRequest,
                        selection: $selection
                    )
                    .frame(height: 132)
                    .overlay {
                        UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                            .stroke(MailTheme.border, lineWidth: 1)
                    }
                }

                if isLinkEditorPresented {
                    HStack(alignment: .bottom, spacing: 8) {
                        compactField("Link text", placeholder: "Display text", text: $linkText)
                        compactField("Web address", placeholder: "https://your-site.com", text: $linkURL)
                        Button("Apply link", action: applyLink)
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(normalizedURL == nil || linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                HStack {
                    Text(status)
                        .font(MailTheme.font(12))
                        .foregroundStyle(MailTheme.secondaryText)

                    Spacer()

                    Button("Cancel") {
                        store.commandPaletteMode = .commands
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button("Save signature", action: save)
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 6)
            .padding(.top, 16)
            .padding(.bottom, 6)
        }
        .onAppear(perform: load)
    }

    private func signatureFormatButton(
        _ title: String,
        weight: Font.Weight = .medium,
        italic: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(MailTheme.font(13, weight: weight))
                .italic(italic)
                .foregroundStyle(MailTheme.text)
                .frame(width: 32, height: 32)
                .background(MailTheme.secondarySurface)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func compactField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(MailTheme.font(12))
                .foregroundStyle(MailTheme.secondaryText)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(MailTheme.font(13))
                .padding(.horizontal, 9)
                .frame(height: 36)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(MailTheme.border, lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity)
    }

    private func prepareLinkEditor() {
        let string = signature.string as NSString
        if selection.location != NSNotFound, NSMaxRange(selection) <= string.length, selection.length > 0 {
            linkText = string.substring(with: selection)
        } else {
            linkText = ""
        }
        linkURL = ""
        status = ""
        isLinkEditorPresented = true
    }

    private func applyLink() {
        guard let url = normalizedURL else {
            status = "Enter a valid web address."
            return
        }
        editorRequest = SignatureEditorRequest(
            command: .link(url: url, displayText: linkText, range: selection)
        )
        isLinkEditorPresented = false
        status = "Link added"
    }

    private var normalizedURL: URL? {
        let trimmed = linkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func save() {
        let range = NSRange(location: 0, length: signature.length)
        guard let rtf = try? signature.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) else {
            status = "Could not save this signature."
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(signatureName.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "keyboard-mail-signature-name")
        defaults.set(rtf, forKey: "keyboard-mail-signature-rtf")
        status = "Saved locally"
    }

    private func load() {
        let defaults = UserDefaults.standard
        signatureName = defaults.string(forKey: "keyboard-mail-signature-name") ?? "Default"
        guard let data = defaults.data(forKey: "keyboard-mail-signature-rtf"),
              let loaded = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
              ) else { return }
        signature = loaded
    }
}

enum SignatureEditorCommand {
    case bold
    case italic
    case link(url: URL, displayText: String, range: NSRange)
}

struct SignatureEditorRequest {
    let id = UUID()
    let command: SignatureEditorCommand
}

private struct RichSignatureEditor: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    var request: SignatureEditorRequest?
    @Binding var selection: NSRange

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14, weight: .regular)
        textView.textColor = Self.textColor
        textView.insertionPointColor = Self.textColor
        textView.textContainerInset = NSSize(width: 13, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.linkTextAttributes = [
            .foregroundColor: Self.textColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.textStorage?.setAttributedString(attributedText)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.lastRequestID = request?.id
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if !textView.attributedString().isEqual(to: attributedText) {
            textView.textStorage?.setAttributedString(attributedText)
        }

        if let request, request.id != context.coordinator.lastRequestID {
            context.coordinator.lastRequestID = request.id
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                Self.perform(request.command, in: textView)
                context.coordinator.syncFromEditor()
            }
        }
    }

    private static func perform(_ command: SignatureEditorCommand, in textView: NSTextView) {
        switch command {
        case .bold:
            toggleFontTrait(.boldFontMask, in: textView)
        case .italic:
            toggleFontTrait(.italicFontMask, in: textView)
        case .link(let url, let displayText, let requestedRange):
            let storage = textView.textStorage ?? NSTextStorage()
            let validRange: NSRange
            if requestedRange.location != NSNotFound, NSMaxRange(requestedRange) <= storage.length {
                validRange = requestedRange
            } else {
                validRange = textView.selectedRange()
            }

            let replacement = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetRange: NSRange
            if !replacement.isEmpty {
                storage.replaceCharacters(in: validRange, with: replacement)
                targetRange = NSRange(location: validRange.location, length: (replacement as NSString).length)
            } else {
                targetRange = validRange
            }

            guard targetRange.length > 0 else { return }
            storage.addAttributes([
                .link: url,
                .foregroundColor: textColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .font: NSFont.systemFont(ofSize: 14, weight: .regular)
            ], range: targetRange)
            textView.setSelectedRange(NSRange(location: NSMaxRange(targetRange), length: 0))
            var typingAttributes = textView.typingAttributes
            typingAttributes.removeValue(forKey: .link)
            typingAttributes.removeValue(forKey: .underlineStyle)
            textView.typingAttributes = typingAttributes
            textView.didChangeText()
        }
    }

    private static func toggleFontTrait(_ trait: NSFontTraitMask, in textView: NSTextView) {
        let manager = NSFontManager.shared
        let selectedRange = textView.selectedRange()

        if selectedRange.length == 0 {
            var attributes = textView.typingAttributes
            let current = attributes[.font] as? NSFont ?? .systemFont(ofSize: 14)
            let alreadyApplied = manager.traits(of: current).contains(trait)
            attributes[.font] = alreadyApplied
                ? manager.convert(current, toNotHaveTrait: trait)
                : manager.convert(current, toHaveTrait: trait)
            textView.typingAttributes = attributes
            return
        }

        let storage = textView.textStorage ?? NSTextStorage()
        let firstFont = storage.attribute(.font, at: selectedRange.location, effectiveRange: nil) as? NSFont
            ?? .systemFont(ofSize: 14)
        let shouldRemove = manager.traits(of: firstFont).contains(trait)

        storage.enumerateAttribute(.font, in: selectedRange) { value, range, _ in
            let font = value as? NSFont ?? .systemFont(ofSize: 14)
            let converted = shouldRemove
                ? manager.convert(font, toNotHaveTrait: trait)
                : manager.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: converted, range: range)
        }
        textView.didChangeText()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichSignatureEditor
        var lastRequestID: UUID?
        weak var textView: NSTextView?

        init(parent: RichSignatureEditor) {
            self.parent = parent
            lastRequestID = parent.request?.id
        }

        func textDidChange(_ notification: Notification) {
            syncFromEditor()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.selection = textView.selectedRange()
        }

        func syncFromEditor() {
            guard let textView else { return }
            parent.attributedText = NSAttributedString(attributedString: textView.attributedString())
            parent.selection = textView.selectedRange()
        }
    }

    private static let textColor = NSColor(calibratedRed: 41 / 255, green: 41 / 255, blue: 41 / 255, alpha: 1)
}
