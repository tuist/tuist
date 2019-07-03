import Foundation
import XcodeProj

final class SettingsHelper {
    func extend(buildSettings: inout [String: Any], with other: [String: Any], sdk: String? = nil) {
        other.forEach { _key, value in

            let key: String

            if let sdk = sdk {
                key = "\(_key)[sdk=\(sdk)*]"
            } else {
                key = _key
            }

            if buildSettings[key] == nil || (value as? String)?.contains("$(inherited)") == false {
                buildSettings[key] = value
            } else if let previousValueString = buildSettings[key] as? String, let newValueString = value as? String,
                previousValueString != newValueString {
                buildSettings[key] = "\(previousValueString) \(newValueString)"
            } else {
                buildSettings[key] = value
            }
        }
    }

    func settingsProviderPlatform(_ platform: Platform) -> BuildSettingsProvider.Platform {
        switch platform {
        case .iOS: return .iOS
        case .macOS: return .macOS
        case .tvOS: return .tvOS
        }
    }

    func settingsProviderProduct(_ target: Target) -> BuildSettingsProvider.Product? {
        switch target.product {
        case .app:
            return .application
        case .dynamicLibrary:
            return .dynamicLibrary
        case .staticLibrary:
            return .staticLibrary
        case .framework, .staticFramework:
            return .framework
        default:
            return nil
        }
    }

    func variant(_ buildConfiguration: BuildConfiguration) -> BuildSettingsProvider.Variant {
        return buildConfiguration.variant == .debug ? .debug : .release
    }
}
