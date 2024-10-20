//
//  PaymentTextField.swift
//  SharedUI
//
//  Created by Rhys Morgan on 20/10/2024.
//

import StripePaymentsUI
import SwiftUI
import UIKit

public final class PaymentTextField: STPPaymentCardTextField, STPPaymentCardTextFieldDelegate {
  public init() {
    super.init(frame: .zero)
    self.delegate = self
  }
  
  public required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

public struct PaymentTextFieldRepresentable: UIViewRepresentable {
  public init() {}

  public func makeUIView(context: Context) -> PaymentTextField {
    .init()
  }
  
  public func updateUIView(_ uiView: PaymentTextField, context: Context) {}
}
