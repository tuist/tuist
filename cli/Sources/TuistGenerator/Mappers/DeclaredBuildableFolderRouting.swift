import Path
import XcodeGraph

/// Splits a buildable folder that declares both sources and resources between a static target and its companion
/// resource bundle.
///
/// Xcode applies `EXCLUDED_SOURCE_FILE_NAMES` / `INCLUDED_SOURCE_FILE_NAMES` to synchronized folder members in every
/// build phase, but `*` doesn't match `/` and `**` isn't supported. The static target's patterns therefore go one level
/// at a time down to `maximumDepth`, and deeper resources are also copied into it.
struct DeclaredBuildableFolderRouting {
    static let maximumDepth = 8

    private static let excludedKey = "EXCLUDED_SOURCE_FILE_NAMES"
    private static let includedKey = "INCLUDED_SOURCE_FILE_NAMES"

    private static let sourceExtensions: [String] = (
        Target.validSourceExtensions
            + Target.validSourceCompatibleFolderExtensions
            + Target.validHeaderExtensions
    ).filter { $0 != "metal" }

    private static let sharedCatalogExtensions = ["xcassets", "xcstrings"]

    let folders: [AbsolutePath]
    let sourceRootPath: AbsolutePath

    func originalTargetSettings() -> [String: [String]] {
        guard !folders.isEmpty else { return [:] }
        let directories = folders.flatMap { folder in
            (0 ..< Self.maximumDepth).map { depth in
                "$(SRCROOT)/" + ([folder.relative(to: sourceRootPath).pathString] + Array(repeating: "*", count: depth))
                    .joined(separator: "/")
            }
        }
        return [
            Self.excludedKey: directories.map { quoted("\($0)/*") },
            Self.includedKey: directories.flatMap { directory in
                (Self.sourceExtensions + Self.sharedCatalogExtensions).map { quoted("\(directory)/*.\($0)") }
            },
        ]
    }

    func bundleTargetSettings() -> [String: [String]] {
        guard !folders.isEmpty else { return [:] }
        return [Self.excludedKey: Self.sourceExtensions.map { "*.\($0)" }]
    }

    /// Quoted so Xcode keeps a path with spaces as one list element.
    private func quoted(_ pattern: String) -> String {
        "\"\(pattern)\""
    }
}

extension Target {
    /// Keeps what the target already sets.
    func appendingListSettings(_ additions: [String: [String]]) -> Target {
        guard !additions.isEmpty else { return self }

        func appending(_ values: [String], to value: SettingValue?) -> SettingValue {
            switch value {
            case let .array(existing):
                return .array(existing + values.filter { !existing.contains($0) })
            case let .string(existing):
                return .array([existing] + values)
            case nil:
                return .array(["$(inherited)"] + values)
            }
        }

        var base = settings?.base ?? SettingsDictionary()
        var baseDebug = settings?.baseDebug ?? SettingsDictionary()
        var configurations = settings?.configurations ?? [:]
        for (key, values) in additions {
            base[key] = appending(values, to: base[key])
            if baseDebug[key] != nil {
                baseDebug[key] = appending(values, to: baseDebug[key])
            }
            for (buildConfiguration, configuration) in configurations {
                guard var configuration, configuration.settings[key] != nil else { continue }
                configuration.settings[key] = appending(values, to: configuration.settings[key])
                configurations[buildConfiguration] = configuration
            }
        }

        var target = self
        target.settings = settings.map {
            Settings(
                base: base,
                baseDebug: baseDebug,
                configurations: configurations,
                defaultSettings: $0.defaultSettings,
                defaultConfiguration: $0.defaultConfiguration
            )
        } ?? Settings(base: base, configurations: [:])
        return target
    }
}
