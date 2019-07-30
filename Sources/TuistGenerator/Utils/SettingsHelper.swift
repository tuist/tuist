import Foundation
import XcodeProj

final class SettingsHelper {
    func extend(buildSettings: inout [String: SettingValue],
                with other: [String: SettingValue]) {
        other.forEach { key, newValue in
            buildSettings[key] = resolveValue(oldValue: buildSettings[key], newValue: newValue)
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

    // MARK: - Private

    private func resolveValue(oldValue: SettingValue?, newValue: SettingValue) -> SettingValue {
        guard let oldValue = oldValue else {
            return newValue
        }
        guard oldValue != newValue else {
            return oldValue
        }

        switch (oldValue, newValue) {
        case let (.string(old), .string(new)) where new.contains("$(inherited)"):
            return .array([old, new].uniqued())
        case let (.string(old), .array(new)) where new.contains("$(inherited)"):
            return .array(([old] + new).uniqued())
        case let (.array(old), .string(new)) where new.contains("$(inherited)"):
            return .array((old + [new]).uniqued())
        case let (.array(old), .array(new)) where new.contains("$(inherited)"):
            return .array((old + new).uniqued())
        default:
            return newValue
        }
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        return Set(self).sorted()
    }
}
