import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            finish()
            return
        }

        // URL型を優先、なければテキスト型にフォールバック
        if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] result, _ in
                let urlString = (result as? URL)?.absoluteString
                    ?? (result as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil)?.absoluteString }
                DispatchQueue.main.async {
                    self?.handleURLString(urlString)
                }
            }
        } else if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] result, _ in
                let urlString = result as? String
                DispatchQueue.main.async {
                    self?.handleURLString(urlString)
                }
            }
        } else {
            finish()
        }
    }

    private func handleURLString(_ urlString: String?) {
        guard let urlString, urlString.contains("youtube.com/watch") else {
            finish()
            return
        }
        openMainApp(with: urlString)
    }

    private func openMainApp(with youtubeURL: String) {
        guard let encoded = youtubeURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let appURL = URL(string: "livelens://analyze?url=\(encoded)") else {
            finish()
            return
        }
        extensionContext?.open(appURL) { [weak self] _ in
            self?.finish()
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
