import AppKit
import UniformTypeIdentifiers

@MainActor
final class AttachmentPickerController {
    static let shared = AttachmentPickerController()

    private let panel: NSOpenPanel
    private var completion: (([URL]) -> Void)?

    private init() {
        let panel = NSOpenPanel()
        panel.title = "Attach files"
        panel.prompt = "Attach"
        panel.allowedContentTypes = [.item]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = false
        self.panel = panel
    }

    func prewarm() {
        _ = panel.contentView
    }

    func present(completion: @escaping ([URL]) -> Void) {
        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        self.completion = completion
        panel.begin { [weak self] response in
            guard let self else { return }
            let urls = response == .OK ? panel.urls : []
            let handler = self.completion
            self.completion = nil
            handler?(urls)
        }
    }
}
