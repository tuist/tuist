import Foundation
import UIKit

public class StaticFramework2Resources {
    public let name = "StaticFramework2Resources"
    public init() {

    }

    public func loadImage() -> UIImage? {
        return UIImage(named: "StaticFramework3Resources-tuist",
                       in: .staticFramework3,
                       compatibleWith: nil)
    }
}
