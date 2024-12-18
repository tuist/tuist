import Foundation
import SwiftUI
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

    public func loadUIImageWithSynthesizedAccessors() -> UIImage {
        UIImage(resource: StaticFramework3Images.assetCatalogLogo)
    }

    public func loadImageWithSynthesizedAccessors() -> Image {
        Image(StaticFramework3Images.assetCatalogLogo)
    }
}
