import StripePaymentsUI
import SwiftUI
import UIKit

public final class PaymentTextField: STPPaymentCardTextField, STPPaymentCardTextFieldDelegate {
    public init() {
        super.init(frame: .zero)
        delegate = self
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public struct PaymentTextFieldRepresentable: UIViewRepresentable {
    public init() {}

    public func makeUIView(context _: Context) -> PaymentTextField {
        .init()
    }

    public func updateUIView(_: PaymentTextField, context _: Context) {}
}
