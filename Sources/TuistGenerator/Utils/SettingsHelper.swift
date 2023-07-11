import Foundation
import TuistCore
import TuistGraph
import XcodeProj

final class SettingsHelper {
    func extend(
        buildSettings: inout SettingsDictionary,
        with other: SettingsDictionary
    ) {
        other.forEach { key, newValue in
            buildSettings[key] = merge(oldValue: buildSettings[key], newValue: newValue).normalize()
        }
    }

    func extend(
        buildSettings: inout [String: Any],
        with other: SettingsDictionary
    ) throws {
        var settings = try buildSettings.toSettings()
        extend(buildSettings: &settings, with: other)
        buildSettings = settings.toAny()
    }

    func settingsProviderPlatform(_ target: Target) -> BuildSettingsProvider.Platform? {
        switch target.platform {
        case .iOS: return .iOS
        case .macOS: return .macOS
        case .tvOS: return .tvOS
        case .watchOS: return .watchOS
        case .visionOS: return .visionOS
        }
    }

    func settingsProviderProduct(_ target: Target) -> BuildSettingsProvider.Product? {
        switch target.product {
        case .app, .watch2App, .appClip:
            return .application
        case .dynamicLibrary:
            return .dynamicLibrary
        case .staticLibrary:
            return .staticLibrary
        case .framework, .staticFramework:
            return .framework
        case .appExtension, .messagesExtension, .extensionKitExtension:
            return .appExtension
        case .watch2Extension:
            return .watchExtension
        case .unitTests:
            return .unitTests
        case .uiTests:
            return .uiTests
        default:
            return nil
        }
    }

    func variant(_ buildConfiguration: BuildConfiguration) -> BuildSettingsProvider.Variant {
        buildConfiguration.variant == .debug ? .debug : .release
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
        // The .sortAndTrim() method ensures the result of merging does not contain duplicate "$(inherited)" and that "$(inherited)" is the first element
        // i.e. merging the following values:
        // oldValue = ["$(inherited)", "VALUE_1"]
        // newValue = ["$(inherited)", "VALUE_2"]
        // would result in ["$(inherited)", "$(inherited)", "VALUE_1", "VALUE_2"] if .sortAndTrim() was not used.
        let inherited = "$(inherited)"
        switch (oldValue, newValue) {
        case let (.string(old), .string(new)) where new.contains(inherited):
            // Example: ("OLD", "$(inherited) NEW") -> ["$(inherited) NEW", "OLD"]
            // This case shouldn't happen as all default multi-value settings are defined as NSArray<NSString>
            return .array(Self.sortAndTrim(array: [old, new], element: inherited))

        case let (.string(old), .array(new)) where new.contains(inherited):
            // Example: ("OLD", ["$(inherited)", "NEW"]) -> ["$(inherited)", "NEW", "OLD"]
            return .array(Self.sortAndTrim(array: [old] + new, element: inherited))

        case let (.array(old), .string(new)) where new.contains(inherited):
            // Example: (["OLD", "OLD_2"], "$(inherited) NEW") -> ["$(inherited) NEW", "OLD", "OLD_2"]
            // This case shouldn't happen as all default multi-value settings are defined as NSArray<NSString>
            return .array(Self.sortAndTrim(array: old + [new], element: inherited))

        case let (.array(old), .array(new)) where new.contains(inherited):
            // Example: (["OLD", "OLD_2"], ["$(inherited)", "NEW"]) -> ["$(inherited)", "NEW", "OLD", OLD_2"]
            return .array(Self.sortAndTrim(array: old + new, element: inherited))

        default:
            // The newValue does not contain $(inherited) so the oldValue should be omitted
            return newValue
        }
    }

    private static func sortAndTrim(array: [String], element: String) -> [String] {
        guard array.contains(where: { $0.starts(with: element) }) else { return array }
        // Move items that contain `element` to the top of the array
        return array
            .sorted { first, _ in first.contains(element) }
            .enumerated()
            .compactMap { index, item in
                // Remove duplicate `element`
                if index > 0,
                   item == element
                {
                    return nil
                } else if index > 0, item.contains(element) {
                    // "$(inherited) flag" -> "flag"
                    return item
                        .replacingOccurrences(of: element, with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    return item
                }
            }
    }
}
