import Foundation
import XcodeProj

final class SettingsHelper {
    func extend(buildSettings: inout [String: Any], with other: [String: Any]) {
        other.forEach { key, value in
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

    func settingsProviderPlatform(_ target: Target) -> BuildSettingsProvider.Platform? {
        var platform: BuildSettingsProvider.Platform?
        switch target.platform {
        case .iOS: platform = .iOS
        case .macOS: platform = .macOS
        case .tvOS: platform = .tvOS
            // case .watchOS: platform = .watchOS
        }
        return platform
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
