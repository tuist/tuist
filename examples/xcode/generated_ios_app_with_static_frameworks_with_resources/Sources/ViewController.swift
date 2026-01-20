import A
import Foundation
import UIKit

final class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .orange

        let customView = CustomView()
        customView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(customView)
        NSLayoutConstraint.activate([
            customView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            customView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
