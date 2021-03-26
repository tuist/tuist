import Foundation
import UIKit

public class ResourcesStaticFramework4 {
    public let name = "StaticFramework4Resources"
    public init() {

    }

    public func loadImage() -> UIImage? {
        return UIImage(named: "StaticFramework4Resources-tuist",
                       in: StaticFramework4Resources.bundle,
                       compatibleWith: nil)
    }
}
