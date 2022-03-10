import Foundation
import UIKit

final class DloadFramework: UIView {
  override public init(frame: CGRect) {
    super.init(frame: frame)
    print("DloadFramework.hello()")
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
