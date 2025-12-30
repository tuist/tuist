import Foundation
import UIKit

public final class CustomView: UIView {
    private let label = UILabel()
    override public init(frame: CGRect) {
        super.init(frame: frame)

        label.font = UIFont(font: AFontFamily.Poppins.regular, size: 20.0)
        label.text = "Custom View"
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
