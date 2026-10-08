import SwiftUI
import TuistAuthentication
import TuistNoora
import UIKit

/// Presents the self-hosted server prompt with UIKit because SwiftUI alerts can't render
/// "Save & Continue" as the prominent, accent-filled action from the design.
@MainActor
enum SelfHostedServerAlert {
    static func present(serverURL: String, onSave: @escaping (String) -> Void) {
        guard let presenter = topViewController() else { return }

        let alert = UIAlertController(
            title: "Self-hosted",
            message: "Use the root address of your Tuist server",
            preferredStyle: .alert
        )
        let save = UIAlertAction(title: "Save & Continue", style: .default) { [weak alert] _ in
            onSave(alert?.textFields?.first?.text ?? "")
        }
        save.isEnabled = isValid(serverURL)

        alert.addTextField { field in
            field.text = serverURL
            field.placeholder = "https://example.com"
            field.keyboardType = .URL
            field.textContentType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
            field.addAction(UIAction { [weak save, weak field] _ in
                save?.isEnabled = isValid(field?.text ?? "")
            }, for: .editingChanged)
        }
        alert.addAction(save)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.preferredAction = save
        alert.view.tintColor = UIColor(Noora.Colors.accent)

        presenter.present(alert, animated: true)
    }

    private static func isValid(_ serverURL: String) -> Bool {
        (try? AppServerEnvironmentService.validatedURL(serverURL)) != nil
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
