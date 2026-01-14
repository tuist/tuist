import Foundation
import UIKit

public enum LocalAssetsProvider {
    public static func sampleText() -> String? {
        guard let url = Bundle.module.url(forResource: "Sample", withExtension: "txt"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public static func accentColor() -> UIColor? {
        return UIColor(named: "AccentColor", in: Bundle.module, compatibleWith: nil)
    }
}
