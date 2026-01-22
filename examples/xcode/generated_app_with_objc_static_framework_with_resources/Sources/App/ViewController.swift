import SVProgressHUD
import UIKit

class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let button = UIButton(type: .system)
        button.setTitle("Show Progress", for: .normal)
        button.addTarget(self, action: #selector(showProgress), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)

        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @objc func showProgress() {
        SVProgressHUD.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            SVProgressHUD.dismiss()
        }
    }
}
