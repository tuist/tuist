// MARK: PackageInfo

/// The Swift Package Manager package information.
/// It decodes data encoded from Manifest.swift: https://github.com/apple/swift-package-manager/blob/06f9b30f4593940272f57f6284e5614d817d2f22/Sources/PackageModel/Manifest.swift#L372-L409
/// Fields not needed by tuist are commented out and not decoded at all.
public struct PackageInfo: Decodable, Equatable {
    /// The declared platforms in the manifest.
    public let platforms: [Platform]

    /// The targets declared in the manifest.
    public let targets: [Target]

    // TODO: verify whether these properties are required to generate the Tuist graph

    // Ignored fields

    // /// The name of the package.
    // public let name: String

    // /// The tools version declared in the manifest.
    // public let toolsVersion: ToolsVersion

    // /// The pkg-config name of a system package.
    // public let pkgConfig: String?

    // /// The system package providers of a system package.
    // public let providers: [SystemPackageProviderDescription]?

    // /// The C language standard flag.
    // public let cLanguageStandard: String?

    // /// The C++ language standard flag.
    // public let cxxLanguageStandard: String?

    // /// The supported Swift language versions of the package.
    // public let swiftLanguageVersions: [SwiftLanguageVersion]?

    // /// The declared package dependencies.
    // public let dependencies: [PackageDependencyDescription]

    // /// The products declared in the manifest.
    // public let products: [ProductDescription]

    // /// Whether kind of package this manifest is from.
    // public let packageKind: PackageReference.Kind

    public init(platforms: [Platform], targets: [Target]) {
        self.platforms = platforms
        self.targets = targets
    }
}

// MARK: Platform

extension PackageInfo {
    public struct Platform: Decodable, Equatable {
        public let platformName: String
        public let version: String
        public let options: [String]
    }
}

// MARK: PackageConditionDescription

extension PackageInfo {
    public struct PackageConditionDescription: Decodable, Equatable {
        public let platformNames: [String]
        public let config: String?
    }
}

// MARK: Target

extension PackageInfo {
    public struct Target: Decodable, Equatable {
        /// The name of the target.
        public let name: String

        /// The custom path of the target.
        public let path: String?

        /// The url of the binary target artifact.
        public let url: String?

        /// The custom sources of the target.
        public let sources: [String]?

        /// The explicitly declared resources of the target.
        public let resources: [Resource]

        /// The exclude patterns.
        public let exclude: [String]

        /// The declared target dependencies.
        public let dependencies: [Dependency]

        /// The custom public headers path.
        public let publicHeadersPath: String?

        /// The type of target.
        public let type: TargetType

        /// The target-specific build settings declared in this target.
        public let settings: [TargetBuildSettingDescription.Setting]

        /// The binary target checksum.
        public let checksum: String?
    }
}

// MARK: Target.Dependency

extension PackageInfo.Target {
    public enum Dependency: Equatable {
        public struct PackageConditionDescription: Decodable, Equatable {
            public let platformNames: [String]
            public let config: String?
        }

        case target(name: String, condition: PackageConditionDescription?)
        case product(name: String, package: String?, condition: PackageConditionDescription?)
        case byName(name: String, condition: PackageConditionDescription?)
    }
}

// MARK: Target.Resource

extension PackageInfo.Target {
    public struct Resource: Decodable, Equatable {
        public enum Rule: String, Decodable, Equatable {
            case process
            case copy
        }

        public enum Localization: String, Decodable, Equatable {
            case `default`
            case base
        }

        /// The rule for the resource.
        public let rule: Rule

        /// The path of the resource.
        public let path: String

        /// The explicit localization of the resource.
        public let localization: Localization?

        public init(rule: Rule, path: String, localization: Localization? = nil) {
            self.rule = rule
            self.path = path
            self.localization = localization
        }
    }
}

// MARK: Target.TargetType

extension PackageInfo.Target {
    public enum TargetType: String, Equatable, Decodable {
        case regular
        case executable
        case test
        case system
        case binary
        case plugin
    }
}

// MARK: Target.TargetBuildSettingDescription

extension PackageInfo.Target {
    /// A namespace for target-specific build settings.
    public enum TargetBuildSettingDescription {

        /// The tool for which a build setting is declared.
        public enum Tool: String, Decodable, Equatable, CaseIterable {
            case c
            case cxx
            case swift
            case linker
        }

        /// The name of the build setting.
        public enum SettingName: String, Decodable, Equatable {
            case headerSearchPath
            case define
            case linkedLibrary
            case linkedFramework
            case unsafeFlags
        }

        /// An individual build setting.
        public struct Setting: Decodable, Equatable {

            /// The tool associated with this setting.
            public let tool: Tool

            /// The name of the setting.
            public let name: SettingName

            /// The condition at which the setting should be applied.
            public let condition: PackageInfo.PackageConditionDescription?

            /// The value of the setting.
            ///
            /// This is kind of like an "untyped" value since the length
            /// of the array will depend on the setting type.
            public let value: [String]
        }
    }
}

// MARK: Decodable conformances

extension PackageInfo.Target.Dependency: Decodable {
    private enum CodingKeys: String, CodingKey {
        case target, product, byName
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = values.allKeys.first(where: values.contains) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
        }

        switch key {
        case .target:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            self = .target(
                name: try unkeyedValues.decode(String.self),
                condition: try unkeyedValues.decodeIfPresent(PackageConditionDescription.self)
            )
        case .product:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            self = .product(
                name: try unkeyedValues.decode(String.self),
                package: try unkeyedValues.decodeIfPresent(String.self),
                condition: try unkeyedValues.decodeIfPresent(PackageConditionDescription.self)
            )
        case .byName:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            self = .byName(
                name: try unkeyedValues.decode(String.self),
                condition: try unkeyedValues.decodeIfPresent(PackageConditionDescription.self)
            )
        }
    }
}
