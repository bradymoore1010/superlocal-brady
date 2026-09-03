import AppKit
import SwiftUI

private extension NSAttributedString.Key {
    static let mailInlineImageID = NSAttributedString.Key("KeyboardFirstMail.inlineImageID")
}

@MainActor
private enum MailTextEditorViewPool {
    private static var idleScrollViews: [NSScrollView] = []

    static func take() -> NSScrollView? {
        idleScrollViews.popLast()
    }

    static func put(_ scrollView: NSScrollView) {
        guard idleScrollViews.count < 2 else { return }
        idleScrollViews.append(scrollView)
    }
}

struct ComposerLinkRequest: Identifiable {
    let id = UUID()
    let selectedText: String
    let anchorRect: CGRect
    let apply: (URL) -> Void
}

struct ComposerImageResizeRequest: Identifiable {
    let id = UUID()
    let imageID: UUID
    let name: String
    let size: InlineImageDisplaySize
    let anchorRect: CGRect
    let apply: (InlineImageDisplaySize) -> Void
}

struct MailTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var inlineImages: [InlineDraftImage]
    var focusRequest = 0
    var formattingRequest: MailEditorRequest?
    var inlineImageRequest: MailInlineImageRequest?
    var accessibilityLabel = "Message body"
    var focusNotification: Notification.Name?
    var onAttachFiles: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var onContentHeightChange: ((CGFloat) -> Void)?
    var onLinkRequested: ((ComposerLinkRequest) -> Void)?
    var onImageResizeRequested: ((ComposerImageResizeRequest) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = MailTextEditorViewPool.take() ?? NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = (scrollView.documentView as? NativeMailTextView) ?? NativeMailTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.availableInlineImages = inlineImages
        textView.font = .systemFont(ofSize: 14, weight: .regular)
        textView.textColor = NSColor(calibratedRed: 41 / 255, green: 41 / 255, blue: 41 / 255, alpha: 1)
        textView.insertionPointColor = NSColor(calibratedRed: 41 / 255, green: 41 / 255, blue: 41 / 255, alpha: 1)
        textView.drawsBackground = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 16, height: 13)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.layoutManager?.backgroundLayoutEnabled = true
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacing = 1
        paragraphStyle.defaultTabInterval = 20
        paragraphStyle.tabStops = (1...12).map {
            NSTextTab(textAlignment: .left, location: CGFloat($0) * 20)
        }
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor(calibratedRed: 41 / 255, green: 41 / 255, blue: 41 / 255, alpha: 1),
            .paragraphStyle: paragraphStyle
        ]
        textView.identifier = NSUserInterfaceItemIdentifier("mail-composer")
        textView.onAttachFiles = onAttachFiles
        textView.onLinkRequested = onLinkRequested
        textView.onImageResizeRequested = onImageResizeRequested
        textView.onGeometryChange = { [weak coordinator = context.coordinator] in
            coordinator?.reportContentHeight()
        }
        textView.linkTextAttributes = [
            .foregroundColor: NSColor(calibratedRed: 41 / 255, green: 41 / 255, blue: 41 / 255, alpha: 1),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.setAccessibilityLabel(accessibilityLabel)

        scrollView.documentView = textView
        textView.restoreInlineImages()
        context.coordinator.textView = textView
        context.coordinator.lastFocusRequest = focusRequest
        context.coordinator.lastFormattingRequestID = formattingRequest?.id
        context.coordinator.lastInlineImageRequestID = inlineImageRequest?.id
        context.coordinator.observeFocusNotification(focusNotification)

        if !text.isEmpty || !inlineImages.isEmpty {
            DispatchQueue.main.async {
                context.coordinator.reportContentHeight()
            }
        }

        if focusRequest > 0 {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NativeMailTextView else { return }
        var needsHeightUpdate = false

        if textView.string != text, !context.coordinator.isPropagatingNativeChange {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.availableInlineImages = inlineImages
            textView.restoreInlineImages()
            let textLength = (text as NSString).length
            let location = min(selectedRange.location, textLength)
            textView.setSelectedRange(
                NSRange(
                    location: location,
                    length: min(selectedRange.length, max(0, textLength - location))
                )
            )
            needsHeightUpdate = true
        } else {
            needsHeightUpdate = textView.availableInlineImages != inlineImages
            textView.availableInlineImages = inlineImages
        }

        textView.onAttachFiles = onAttachFiles
        textView.onLinkRequested = onLinkRequested
        textView.onImageResizeRequested = onImageResizeRequested
        textView.setAccessibilityLabel(accessibilityLabel)

        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        if let formattingRequest,
           context.coordinator.lastFormattingRequestID != formattingRequest.id {
            context.coordinator.lastFormattingRequestID = formattingRequest.id
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                textView.perform(formattingRequest.command)
            }
        }

        if let inlineImageRequest,
           context.coordinator.lastInlineImageRequestID != inlineImageRequest.id {
            context.coordinator.lastInlineImageRequestID = inlineImageRequest.id
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                textView.insertInlineImages(inlineImageRequest.images)
            }
        }

        if needsHeightUpdate {
            DispatchQueue.main.async {
                context.coordinator.reportContentHeight()
            }
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObservingFocus()
        if let textView = scrollView.documentView as? NativeMailTextView {
            textView.delegate = nil
            textView.onAttachFiles = nil
            textView.onLinkRequested = nil
            textView.onImageResizeRequested = nil
            textView.onGeometryChange = nil
        }
        coordinator.textView = nil
        MailTextEditorViewPool.put(scrollView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MailTextEditor
        var lastFocusRequest: Int
        var lastFormattingRequestID: UUID?
        var lastInlineImageRequestID: UUID?
        var lastReportedContentHeight: CGFloat = -1
        var isPropagatingNativeChange = false
        fileprivate weak var textView: NativeMailTextView?
        private var observedFocusNotification: Notification.Name?

        init(parent: MailTextEditor) {
            self.parent = parent
            lastFocusRequest = parent.focusRequest
            lastFormattingRequestID = parent.formattingRequest?.id
            lastInlineImageRequestID = parent.inlineImageRequest?.id
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isPropagatingNativeChange = true
            parent.text = textView.string
            if let nativeTextView = textView as? NativeMailTextView {
                parent.inlineImages = nativeTextView.orderedInlineImages()
            }
            reportContentHeight()
            DispatchQueue.main.async { [weak self] in
                self?.isPropagatingNativeChange = false
            }
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange?(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onFocusChange?(false)
        }

        func reportContentHeight() {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            let lineHeight = layoutManager.defaultLineHeight(for: textView.font ?? .systemFont(ofSize: 14))
            let height = ceil(max(usedHeight, lineHeight) + textView.textContainerInset.height * 2)
            guard abs(height - lastReportedContentHeight) > 0.5 else { return }
            lastReportedContentHeight = height
            parent.onContentHeightChange?(height)
        }

        func observeFocusNotification(_ name: Notification.Name?) {
            stopObservingFocus()

            guard let name else { return }
            observedFocusNotification = name
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFocusRequest(_:)),
                name: name,
                object: nil
            )
        }

        func stopObservingFocus() {
            if let observedFocusNotification {
                NotificationCenter.default.removeObserver(
                    self,
                    name: observedFocusNotification,
                    object: nil
                )
                self.observedFocusNotification = nil
            }
        }

        @objc private func handleFocusRequest(_ notification: Notification) {
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
        }
    }
}

@MainActor
final class NativeMailTextView: NSTextView {
    static weak var activeEditor: NativeMailTextView?
    var onAttachFiles: (() -> Void)?
    var onLinkRequested: ((ComposerLinkRequest) -> Void)?
    var onImageResizeRequested: ((ComposerImageResizeRequest) -> Void)?
    var onGeometryChange: (() -> Void)?
    var availableInlineImages: [InlineDraftImage] = []
    private var activeSlashRange: NSRange?

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.size.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged {
            DispatchQueue.main.async { [weak self] in
                self?.onGeometryChange?()
            }
        }
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder { Self.activeEditor = self }
        return becameFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, Self.activeEditor === self { Self.activeEditor = nil }
        return resigned
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let request = imageResizeRequest(at: point) {
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location: request.characterLocation, length: 1))
            onImageResizeRequested?(request.request)
            return
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let characters = event.charactersIgnoringModifiers?.lowercased()

        if (modifiers == .command || modifiers == .control), characters == "k" {
            requestLink()
            return
        }

        if modifiers.isEmpty,
           let typedCharacter = event.characters,
           (typedCharacter == "/" || typedCharacter == "\\"),
           MailLineFormatter.canPresentSlashMenu(in: string, selection: selectedRange()) {
            showSlashMenu(trigger: typedCharacter)
            return
        }

        if (modifiers.isEmpty || modifiers == .shift), event.keyCode == 49,
           let edit = MailLineFormatter.completeListTrigger(in: string, selection: selectedRange()) {
            apply(edit)
            return
        }

        if modifiers == .command, event.keyCode == 51 {
            apply(MailLineFormatter.commandBackspace(in: string, selection: selectedRange()))
            return
        }

        if modifiers == [.command, .shift], characters == "a" {
            onAttachFiles?()
            return
        }

        if modifiers == [.command, .shift], (characters == "8" || characters == "*") {
            perform(.bulletList)
            return
        }

        if modifiers == [.command, .shift], (characters == "7" || characters == "&") {
            perform(.numberedList)
            return
        }

        if modifiers == .command, characters == "]" {
            perform(.indent)
            return
        }

        if modifiers == .command, characters == "[" {
            perform(.outdent)
            return
        }

        if modifiers.isEmpty, event.keyCode == 36,
           let edit = MailLineFormatter.continueList(in: string, selection: selectedRange()) {
            apply(edit)
            return
        }

        if modifiers.isEmpty, event.keyCode == 51,
           let edit = MailLineFormatter.removeEmptyListPrefix(in: string, selection: selectedRange()) {
            apply(edit)
            return
        }

        if event.keyCode == 48,
           (modifiers.isEmpty || modifiers == .shift),
           MailLineFormatter.isInList(string, selection: selectedRange()) {
            perform(modifiers == .shift ? .outdent : .indent)
            return
        }

        super.keyDown(with: event)
    }

    func perform(_ command: MailEditorCommand) {
        apply(MailLineFormatter.apply(command, to: string, selection: selectedRange()))
    }

    func requestLink() {
        let range = selectedRange()
        guard range.location != NSNotFound, range.length > 0, NSMaxRange(range) <= (string as NSString).length else {
            NSSound.beep()
            return
        }
        let selected = (string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else {
            NSSound.beep()
            return
        }

        onLinkRequested?(
            ComposerLinkRequest(selectedText: selected, anchorRect: selectionAnchorRect(for: range)) { [weak self] url in
                self?.applyLink(url, to: range)
            }
        )
    }

    func insertInlineImages(_ images: [InlineDraftImage]) {
        guard !images.isEmpty, let storage = textStorage else { return }
        let selection = selectedRange()
        let source = string as NSString
        let insertion = NSMutableAttributedString(string: "")

        if selection.location > 0,
           source.character(at: selection.location - 1) != 10 {
            insertion.append(NSAttributedString(string: "\n", attributes: typingAttributes))
        }

        for (index, image) in images.enumerated() {
            if index > 0 {
                insertion.append(NSAttributedString(string: "\n", attributes: typingAttributes))
            }
            insertion.append(inlineAttachment(for: image))
        }

        let selectionEnd = NSMaxRange(selection)
        if selectionEnd >= source.length || source.character(at: selectionEnd) != 10 {
            insertion.append(NSAttributedString(string: "\n", attributes: typingAttributes))
        }

        guard shouldChangeText(in: selection, replacementString: insertion.string) else { return }
        availableInlineImages.append(contentsOf: images)
        storage.beginEditing()
        storage.replaceCharacters(in: selection, with: insertion)
        storage.endEditing()
        let location = selection.location + insertion.length
        setSelectedRange(NSRange(location: location, length: 0))
        didChangeText()
        setSelectedRange(NSRange(location: location, length: 0))
        scrollRangeToVisible(NSRange(location: max(0, location - 1), length: 0))
    }

    func restoreInlineImages() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let source = storage.string as NSString
        var imageIndex = 0

        storage.beginEditing()
        for location in 0..<source.length where source.character(at: location) == 0xFFFC {
            guard imageIndex < availableInlineImages.count else { break }
            let image = availableInlineImages[imageIndex]
            let attachment = inlineAttachment(for: image)
            let attributes = attachment.attributes(at: 0, effectiveRange: nil)
            storage.addAttributes(attributes, range: NSRange(location: location, length: 1))
            imageIndex += 1
        }
        storage.endEditing()
    }

    func orderedInlineImages() -> [InlineDraftImage] {
        guard let storage = textStorage, storage.length > 0 else { return [] }
        let imagesByID = Dictionary(uniqueKeysWithValues: availableInlineImages.map { ($0.id.uuidString, $0) })
        var ordered: [InlineDraftImage] = []
        storage.enumerateAttribute(
            .mailInlineImageID,
            in: NSRange(location: 0, length: storage.length)
        ) { value, _, _ in
            guard let id = value as? String, let image = imagesByID[id] else { return }
            ordered.append(image)
        }
        availableInlineImages = ordered
        return ordered
    }

    private struct ImageResizeHit {
        let characterLocation: Int
        let request: ComposerImageResizeRequest
    }

    private func imageResizeRequest(at point: NSPoint) -> ImageResizeHit? {
        guard let layoutManager,
              let textContainer,
              let storage = textStorage,
              storage.length > 0 else { return nil }

        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        guard containerPoint.x >= 0, containerPoint.y >= 0 else { return nil }

        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: &fraction
        )
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        guard glyphRect.insetBy(dx: -2, dy: -2).contains(containerPoint) else { return nil }

        let characterLocation = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterLocation < storage.length,
              let rawID = storage.attribute(
                .mailInlineImageID,
                at: characterLocation,
                effectiveRange: nil
              ) as? String,
              let image = availableInlineImages.first(where: { $0.id.uuidString == rawID }) else {
            return nil
        }

        let range = NSRange(location: characterLocation, length: 1)
        let request = ComposerImageResizeRequest(
            imageID: image.id,
            name: image.name,
            size: image.displaySize,
            anchorRect: selectionAnchorRect(for: range)
        ) { [weak self] size in
            self?.resizeInlineImage(id: image.id, to: size)
        }
        return ImageResizeHit(characterLocation: characterLocation, request: request)
    }

    private func resizeInlineImage(id: UUID, to size: InlineImageDisplaySize) {
        guard let imageIndex = availableInlineImages.firstIndex(where: { $0.id == id }),
              availableInlineImages[imageIndex].displaySize != size,
              let storage = textStorage else { return }

        availableInlineImages[imageIndex].displaySize = size
        let updatedImage = availableInlineImages[imageIndex]
        var attachmentRange: NSRange?
        storage.enumerateAttribute(
            .mailInlineImageID,
            in: NSRange(location: 0, length: storage.length)
        ) { value, range, stop in
            guard value as? String == id.uuidString else { return }
            attachmentRange = range
            stop.pointee = true
        }
        guard let attachmentRange,
              shouldChangeText(in: attachmentRange, replacementString: MailDraftSerializer.inlineImageMarker) else {
            return
        }

        let replacement = inlineAttachment(for: updatedImage)
        storage.beginEditing()
        storage.replaceCharacters(in: attachmentRange, with: replacement)
        storage.endEditing()
        setSelectedRange(NSRange(location: attachmentRange.location, length: 1))
        didChangeText()
        setSelectedRange(NSRange(location: attachmentRange.location, length: 1))
        scrollRangeToVisible(attachmentRange)
        onGeometryChange?()
    }

    private func inlineAttachment(for image: InlineDraftImage) -> NSAttributedString {
        guard let sourceImage = NSImage(data: image.data) else {
            return NSAttributedString(string: "[Image: \(image.name)]", attributes: typingAttributes)
        }

        let sizeLimit = image.displaySize.maximumSize
        let availableWidth = min(sizeLimit.width, max(120, bounds.width - textContainerInset.width * 2))
        let availableHeight = sizeLimit.height
        let scale = min(1, availableWidth / max(sourceImage.size.width, 1), availableHeight / max(sourceImage.size.height, 1))
        let targetSize = NSSize(
            width: floor(sourceImage.size.width * scale),
            height: floor(sourceImage.size.height * scale)
        )
        let renderedImage = NSImage(size: targetSize)
        renderedImage.lockFocus()
        sourceImage.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: sourceImage.size),
            operation: .sourceOver,
            fraction: 1
        )
        renderedImage.unlockFocus()

        let attachment = NSTextAttachment()
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: renderedImage)
        let attributed = NSMutableAttributedString(attachment: attachment)
        attributed.addAttribute(
            .mailInlineImageID,
            value: image.id.uuidString,
            range: NSRange(location: 0, length: attributed.length)
        )

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.paragraphSpacingBefore = 8
        paragraphStyle.paragraphSpacing = 8
        attributed.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: attributed.length)
        )
        return attributed
    }

    private func showSlashMenu(trigger: String) {
        let insertionRange = selectedRange()
        insertText(trigger, replacementRange: insertionRange)
        activeSlashRange = NSRange(location: insertionRange.location, length: (trigger as NSString).length)

        let menu = NSMenu(title: "Formatting")
        menu.autoenablesItems = false
        menu.minimumWidth = 224

        [.bulletList, .dashList, .numberedList].forEach { addSlashItem($0, to: menu) }
        menu.addItem(.separator())
        [.indent, .outdent].forEach { addSlashItem($0, to: menu) }

        menu.popUp(positioning: nil, at: slashMenuAnchorPoint(), in: self)
        activeSlashRange = nil
    }

    private func addSlashItem(_ command: MailEditorCommand, to menu: NSMenu) {
        let item = NSMenuItem(
            title: command.title,
            action: #selector(performSlashCommand(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = command.rawValue

        if let image = NSImage(systemSymbolName: command.systemImage, accessibilityDescription: command.title) {
            image.isTemplate = true
            image.size = NSSize(width: 14, height: 14)
            item.image = image
        }

        switch command {
        case .bulletList:
            item.keyEquivalent = "8"
            item.keyEquivalentModifierMask = [.command, .shift]
        case .numberedList:
            item.keyEquivalent = "7"
            item.keyEquivalentModifierMask = [.command, .shift]
        case .indent:
            item.keyEquivalent = "]"
            item.keyEquivalentModifierMask = .command
        case .outdent:
            item.keyEquivalent = "["
            item.keyEquivalentModifierMask = .command
        case .dashList:
            break
        }

        menu.addItem(item)
    }

    @objc private func performSlashCommand(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let command = MailEditorCommand(rawValue: rawValue) else { return }
        removeActiveSlashTrigger()
        perform(command)
    }

    private func removeActiveSlashTrigger() {
        guard let range = activeSlashRange,
              let storage = textStorage,
              NSMaxRange(range) <= storage.length else { return }
        let marker = storage.attributedSubstring(from: range).string
        guard marker == "/" || marker == "\\",
              shouldChangeText(in: range, replacementString: "") else { return }

        storage.beginEditing()
        storage.replaceCharacters(in: range, with: "")
        storage.endEditing()
        setSelectedRange(NSRange(location: range.location, length: 0))
        didChangeText()
        setSelectedRange(NSRange(location: range.location, length: 0))
        activeSlashRange = nil
    }

    private func slashMenuAnchorPoint() -> NSPoint {
        guard let layoutManager, let textContainer, !string.isEmpty else {
            return NSPoint(x: textContainerInset.width, y: textContainerInset.height + 24)
        }

        let characterIndex = max(0, min(selectedRange().location - 1, (string as NSString).length - 1))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        let origin = textContainerOrigin
        return NSPoint(x: glyphRect.minX + origin.x, y: lineRect.maxY + origin.y + 8)
    }

    private func selectionAnchorRect(for range: NSRange) -> CGRect {
        guard let scrollView = enclosingScrollView, let window else {
            return CGRect(x: 16, y: 16, width: 2, height: 18)
        }

        var actualRange = NSRange(location: NSNotFound, length: 0)
        let screenRect = firstRect(forCharacterRange: range, actualRange: &actualRange)
        let windowRect = window.convertFromScreen(screenRect)
        let localRect = scrollView.convert(windowRect, from: nil)
        let y = scrollView.isFlipped
            ? localRect.minY
            : scrollView.bounds.height - localRect.maxY

        return CGRect(
            x: max(8, localRect.minX),
            y: max(4, y),
            width: max(2, localRect.width),
            height: max(18, localRect.height)
        )
    }

    private func apply(_ edit: MailTextEdit?) {
        guard let edit else { return }
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.beginEditing()
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        textStorage?.endEditing()
        setSelectedRange(edit.selection)
        didChangeText()
        setSelectedRange(edit.selection)
        scrollRangeToVisible(edit.selection)
    }

    private func applyLink(_ url: URL, to range: NSRange) {
        guard let storage = textStorage, range.location != NSNotFound, NSMaxRange(range) <= storage.length else { return }
        storage.addAttributes([
            .link: url,
            .foregroundColor: NSColor(calibratedRed: 41 / 255, green: 41 / 255, blue: 41 / 255, alpha: 1),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ], range: range)
        setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
        var attributes = typingAttributes
        attributes.removeValue(forKey: .link)
        attributes.removeValue(forKey: .underlineStyle)
        typingAttributes = attributes
        didChangeText()
        scrollRangeToVisible(range)
    }
}
