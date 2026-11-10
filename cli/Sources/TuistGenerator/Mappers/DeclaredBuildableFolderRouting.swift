import Path
import XcodeGraph

/// Splits a buildable folder that declares both sources and resources between a static target and its companion
/// resource bundle without knowing the folder's files.
///
/// Both targets reference the whole folder, and `EXCLUDED_SOURCE_FILE_NAMES` / `INCLUDED_SOURCE_FILE_NAMES` route its
/// files by type, including files written after generation. Xcode matches those `fnmatch(3)` patterns against each
/// file's path in every build phase, synchronized folder members included, but `*` doesn't match `/` and `**` isn't
/// supported, so:
///   - the bundle excludes sources and headers by file name, at any depth. It compiles nothing but `.metal` files, so
///     the patterns don't need a path;
///   - the static target excludes the folder's files and re-includes sources, headers and catalogs, with one pattern
///     per directory level down to `maximumDepth`. Deeper resources are also copied into the static target;
///     deeper sources are still compiled only there.
///
/// This matches how `BuildableFolderResourcePartitioner` routes files it can see.
struct DeclaredBuildableFolderRouting {
    static let maximumDepth = 4

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
    /// Appends `values` to the list settings in `additions`, in the base settings and in every configuration that
    /// overrides them, keeping what the target already sets.
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
        var configurations = settings?.configurations ?? [:]
        for (key, values) in additions {
            base[key] = appending(values, to: base[key])
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
                baseDebug: $0.baseDebug,
                configurations: configurations,
                defaultSettings: $0.defaultSettings,
                defaultConfiguration: $0.defaultConfiguration
            )
        } ?? Settings(base: base, configurations: [:])
        return target
    }
}
