import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum ResourcesProvider {
    public static func greeting() -> String {
        let url = Bundle.module.url(forResource: "greeting", withExtension: "txt")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    public static var brandColor: Color {
        Color("BrandColor", bundle: .module)
    }

    public static var brandColorIsLoaded: Bool {
        #if canImport(UIKit)
        return UIColor(named: "BrandColor", in: .module, compatibleWith: nil) != nil
        #elseif canImport(AppKit)
        return NSColor(named: "BrandColor", bundle: .module) != nil
        #else
        return false
        #endif
    }
}
