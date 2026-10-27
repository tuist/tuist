import Social
import UIKit
import UniformTypeIdentifiers

@objc(ShareViewController)
final class ShareViewController: SLComposeServiceViewController {
    private var sharedURL = ""
    private var sharedText = ""
    private var loaded = false
    private var recipient: AtlasShareRecipient?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Save to Atlas"
        navigationItem.rightBarButtonItem?.title = "Save"
        placeholder = "Add a note (optional)"
        textView.text = ""
        Task { await loadShare() }
    }

    override func isContentValid() -> Bool { loaded && contentText.unicodeScalars.count <= 2000 }

    override func configurationItems() -> [Any]! {
        let item = SLComposeSheetConfigurationItem()!
        item.title = "Moodboard"
        item.value = "Review in Atlas"
        item.tapHandler = {}
        return [item]
    }

    override func didSelectPost() {
        guard loaded, let recipient else { return }
        loaded = false
        validateContent()
        do {
            try AtlasShareInbox.shared().enqueue(url: sharedURL, content: sharedText,
                                                 recipient: recipient, description: contentText)
            let alert = UIAlertController(title: "Saved on this device",
                                          message: "Open Atlas to review suggested fields and add this to your team's Moodboard.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Done", style: .default) { [weak self] _ in
                self?.extensionContext?.completeRequest(returningItems: nil)
            })
            present(alert, animated: true)
        } catch {
            loaded = true
            validateContent()
            show(error)
        }
    }

    @MainActor private func loadShare() async {
        do {
            let recipient = try AtlasShareInbox.shared().recipient()
            let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
            let providers = items.flatMap { $0.attachments ?? [] }
            guard !items.isEmpty, providers.count <= 4 else { throw AtlasShareError.unsupported }
            var texts = items.compactMap { $0.attributedContentText?.string }
            var urls: [String] = []
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    let value = try await load(provider, type: UTType.url.identifier)
                    guard let url = value as? URL else { throw AtlasShareError.unsupported }
                    urls.append(url.absoluteString)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    let value = try await load(provider, type: UTType.plainText.identifier)
                    guard let text = value as? String else { throw AtlasShareError.unsupported }
                    texts.append(text)
                } else {
                    throw AtlasShareError.unsupported
                }
            }
            urls = Array(Set(urls))
            guard urls.count <= 1 else { throw AtlasShareError.unsupported }
            sharedURL = urls.first ?? ""
            var seen: Set<String> = []
            sharedText = texts.filter { $0 != sharedURL && seen.insert($0).inserted }.joined(separator: "\n\n")
            if sharedURL.isEmpty, sharedText.hasPrefix("https://"),
               !sharedText.contains(where: \.isWhitespace) {
                sharedURL = sharedText
                sharedText = ""
            }
            try AtlasShareInbox.validate(url: sharedURL, content: sharedText)
            placeholder = "Note for Moodboard on \(recipient.server.host ?? "Atlas") (optional)"
            self.recipient = recipient
            loaded = true
            validateContent()
        } catch { show(error) }
    }

    private func load(_ provider: NSItemProvider, type: String) async throws -> NSSecureCoding {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let value {
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(throwing: AtlasShareError.unsupported)
                }
            }
        }
    }

    @MainActor private func show(_ error: Error) {
        let alert = UIAlertController(title: "Could not save to Atlas",
                                      message: (error as? AtlasShareError)?.localizedDescription ?? "Could not read this share. Try again.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
