import Foundation
public import SwiftUI

public enum FrameworkResourceProvider {
    public static func logoImage() -> Image {
        let bundle = Bundle.module
        return Image("logo", bundle: bundle)
    }
}
