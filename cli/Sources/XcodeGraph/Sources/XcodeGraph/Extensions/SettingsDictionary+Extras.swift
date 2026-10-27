import Foundation

extension SettingsDictionary {
    /// Overlays a SettingsDictionary by adding a `[sdk=<sdk>*]` qualifier
    /// e.g. for a multiplatform target
    ///  `LD_RUNPATH_SEARCH_PATHS = @executable_path/Frameworks`
    ///  `LD_RUNPATH_SEARCH_PATHS[sdk=macosx*] = @executable_path/../Frameworks`
    public mutating func overlay(
        with other: SettingsDictionary,
        for platform: Platform
    ) {
        for (key, newValue) in other where self[key] != newValue {
            let newKey = "\(key)[sdk=\(platform.xcodeSdkRoot)*]"
            self[newKey] = newValue
            if platform.hasSimulators, let simulatorSDK = platform.xcodeSimulatorSDK {
                let newKey = "\(key)[sdk=\(simulatorSDK)*]"
                self[newKey] = newValue
            }
        }
    }

    /// Combines two `SettingsDictionary`. Instead of overriding values for a duplicate key, it combines them.
    public func combine(with settings: SettingsDictionary) -> SettingsDictionary {
        merging(settings, uniquingKeysWith: { oldValue, newValue in
            let newValues: [String]
            switch newValue {
            case let .string(value):
                newValues = [value]
            case let .array(values):
                newValues = values
            }
            switch oldValue {
            case let .array(values):
                return .array(values + newValues)
            case let .string(value):
                return .array(value.split(separator: " ").map(String.init) + newValues)
            }
        })
    }
}
