import Foundation
import UIKit

public class StaticFramework3Resources {
    public let name = "StaticFramework3Resources"
    public init() {

    }

    public func loadImage() -> UIImage? {
        return UIImage(named: "StaticFramework3Resources-tuist",
                       in: .staticFramework3,
                       compatibleWith: nil)
    }
}
