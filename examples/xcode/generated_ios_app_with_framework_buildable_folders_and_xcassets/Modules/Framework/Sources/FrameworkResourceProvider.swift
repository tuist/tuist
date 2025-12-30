import Foundation
import SwiftUI

public enum FrameworkResourceProvider {
    public static func logoImage() -> Image {
        let bundle = Bundle.module
        return Image("logo", bundle: bundle)
    }
}
