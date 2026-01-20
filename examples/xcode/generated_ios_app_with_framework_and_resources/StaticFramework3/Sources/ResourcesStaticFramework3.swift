import Foundation
import UIKit

public class ResourcesStaticFramework3 {
    public let name = "StaticFramework3Resources"
    public init() {}

    public func loadImage() -> UIImage? {
        UIImage(
            named: "StaticFramework3Resources-tuist",
            in: .module,
            compatibleWith: nil
        )
    }
}
