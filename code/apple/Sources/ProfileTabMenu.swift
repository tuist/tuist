#if os(iOS)
    import SwiftUI
    import UIKit

    struct ProfileTabMenu: UIViewControllerRepresentable {
        var menu: () -> UIMenu

        func makeUIViewController(context _: Context) -> MenuController { MenuController(menu: menu) }
        func updateUIViewController(_ controller: MenuController, context _: Context) {
            controller.menu = menu
            DispatchQueue.main.async { controller.install() }
        }

        static func dismantleUIViewController(_ controller: MenuController, coordinator _: ()) { controller.uninstall() }

        final class MenuController: UIViewController, UIContextMenuInteractionDelegate {
            var menu: () -> UIMenu
            private lazy var interaction = UIContextMenuInteraction(delegate: self)

            init(menu: @escaping () -> UIMenu) {
                self.menu = menu
                super.init(nibName: nil, bundle: nil)
            }

            required init?(coder _: NSCoder) { nil }
            override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); install() }

            func install() {
                var root: UIViewController = self
                while let parent = root.parent {
                    root = parent
                }
                guard let bar = tabBar(in: root), let title = bar.items?.last?.title,
                      let button = profileButton(in: bar, title: title), button !== interaction.view else { return }
                uninstall()
                button.addInteraction(interaction)
            }

            func uninstall() { interaction.view?.removeInteraction(interaction) }

            private func tabBar(in controller: UIViewController) -> UITabBar? {
                if let controller = controller as? UITabBarController { return controller.tabBar }
                return controller.children.compactMap { tabBar(in: $0) }.first
            }

            private func profileButton(in view: UIView, title: String) -> UIView? {
                if view is UIControl,
                   view.accessibilityLabel == title || view.subviews.contains(where: { ($0 as? UILabel)?.text == title })
                {
                    return view
                }
                return view.subviews.reversed().compactMap { profileButton(in: $0, title: title) }.first
            }

            func contextMenuInteraction(
                _: UIContextMenuInteraction,
                configurationForMenuAtLocation _: CGPoint
            ) -> UIContextMenuConfiguration? {
                UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in self.menu() }
            }

            func contextMenuInteraction(
                _ interaction: UIContextMenuInteraction,
                previewForHighlightingMenuWithConfiguration _: UIContextMenuConfiguration
            ) -> UITargetedPreview? {
                guard let button = interaction.view, let window = button.window else { return nil }
                let preview = UIView(frame: CGRect(x: 0, y: 0, width: button.bounds.width, height: 1))
                let parameters = UIPreviewParameters()
                parameters.backgroundColor = .clear
                parameters.shadowPath = UIBezierPath()
                return UITargetedPreview(view: preview, parameters: parameters, target: UIPreviewTarget(
                    container: window, center: button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.minY), to: window)
                ))
            }

            func contextMenuInteraction(
                _ interaction: UIContextMenuInteraction,
                previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration
            ) -> UITargetedPreview? {
                contextMenuInteraction(interaction, previewForHighlightingMenuWithConfiguration: configuration)
            }
        }
    }
#endif
