import AppKit
import UniformTypeIdentifiers

@MainActor
final class GmailCredentialPickerController {
    static let shared = GmailCredentialPickerController()

    private lazy var panel: NSOpenPanel = {
        let panel = NSOpenPanel()
        panel.title = "Choose Google OAuth credentials"
        panel.message = "Choose the Desktop app JSON downloaded from Google Cloud."
        panel.prompt = "Use Credentials"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        return panel
    }()

    func prewarm() {
        _ = panel.contentView
    }

    func present(completion: @escaping (URL?) -> Void) {
        guard panel.sheetParent == nil else { return }
        if let window = MailWindowRegistry.mainWindow {
            panel.beginSheetModal(for: window) { [weak self] response in
                let url = response == .OK ? self?.panel.url : nil
                completion(url)
            }
        } else {
            completion(panel.runModal() == .OK ? panel.url : nil)
        }
    }
}
