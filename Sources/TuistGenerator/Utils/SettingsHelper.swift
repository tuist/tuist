import Foundation
import XcodeProj

final class SettingsHelper {
    func extend(buildSettings: inout [String: SettingValue],
                with other: [String: SettingValue]) {
        other.forEach { key, newValue in
            buildSettings[key] = merge(oldValue: buildSettings[key], newValue: newValue).normalize()
        }
    }

    func extend(buildSettings: inout [String: Any],
                with other: [String: SettingValue]) throws {
        var settings = try buildSettings.toSettings()
        extend(buildSettings: &settings, with: other)
        buildSettings = settings.toAny()
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

    private func merge(oldValue: SettingValue?, newValue: SettingValue) -> SettingValue {
        // No need to merge, just return newValue when the oldValue is nil (buildSettings[key] == nil).
        guard let oldValue = oldValue else {
            return newValue
        }

        // No need to merge, just return oldValue when the newValue is exactly the same.
        guard oldValue != newValue else {
            return oldValue
        }

        // Both the oldValue and newValue are not nil. If the newValue contains $(inherited),
        // it will need to be merged with the oldValue, otherwise the oldValue will be discarded
        // and the newValue returned without merging.
        //
        // The .uniqued() method ensures the result of merging does not contain duplicates
        // and all the elements are sorted, i.e. merging the following values:
        // oldValue = ["$(inherited)", "VALUE_1"]
        // newValue = ["$(inherited)", "VALUE_2"]
        // would result in ["$(inherited)", "$(inherited)", "VALUE_1", "VALUE_2"] if .uniqued() was not used.
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
            // The newValue does not contain $(inherited) so the oldValue should be omitted
            return newValue
        }
    }
}
