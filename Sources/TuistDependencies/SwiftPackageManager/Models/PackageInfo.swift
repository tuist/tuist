// MARK: PackageInfo

/// The Swift Package Manager package information.
/// It decodes data encoded from Manifest.swift: https://github.com/apple/swift-package-manager/blob/06f9b30f4593940272f57f6284e5614d817d2f22/Sources/PackageModel/Manifest.swift#L372-L409
/// Fields not needed by tuist are commented out and not decoded at all.
public struct PackageInfo: Decodable, Equatable {
    /// The products declared in the manifest.
    public let products: [Product]

    /// The targets declared in the manifest.
    public let targets: [Target]

    /// The declared platforms in the manifest.
    public let platforms: [Platform]

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

    // /// Whether kind of package this manifest is from.
    // public let packageKind: PackageReference.Kind

    public init(products: [Product], targets: [Target], platforms: [Platform]) {
        self.products = products
        self.targets = targets
        self.platforms = platforms
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

// MARK: Product

extension PackageInfo {
    public struct Product: Decodable, Equatable {
        /// The name of the product.
        public let name: String

        /// The type of product to create.
        public let type: Product.ProductType

        /// The list of targets to combine to form the product.
        ///
        /// This is never empty, and is only the targets which are required to be in
        /// the product, but not necessarily their transitive dependencies.
        public let targets: [String]
    }
}

extension PackageInfo.Product {
    public enum ProductType: Equatable {
        /// The type of library.
        public enum LibraryType: String, Codable {
            /// Static library.
            case `static`

            /// Dynamic library.
            case dynamic

            /// The type of library is unspecified and should be decided by package manager.
            case automatic
        }

        /// A library product.
        case library(LibraryType)

        /// An executable product.
        case executable

        /// A plugin product.
        case plugin

        /// A test product.
        case test
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
    /// A dependency of the target.
    public enum Dependency: Equatable {
        public struct PackageConditionDescription: Decodable, Equatable {
            public let platformNames: [String]
            public let config: String?
        }

        /// A dependency internal to the same package.
        case target(name: String, condition: PackageConditionDescription?)

        /// A product from a third party package.
        case product(name: String, package: String, condition: PackageConditionDescription?)

        /// A dependency to be resolved by name.
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

        var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
        switch key {
        case .target:
            self = .target(
                name: try unkeyedValues.decode(String.self),
                condition: try unkeyedValues.decodeIfPresent(PackageConditionDescription.self)
            )
        case .product:
            self = .product(
                name: try unkeyedValues.decode(String.self),
                package: try unkeyedValues.decode(String.self),
                condition: try unkeyedValues.decodeIfPresent(PackageConditionDescription.self)
            )
        case .byName:
            self = .byName(
                name: try unkeyedValues.decode(String.self),
                condition: try unkeyedValues.decodeIfPresent(PackageConditionDescription.self)
            )
        }
    }
}

extension PackageInfo.Product.ProductType: Decodable {
    private enum CodingKeys: String, CodingKey {
        case library, executable, plugin, test
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = values.allKeys.first(where: values.contains) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
        }
        switch key {
        case .library:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let libraryType = try unkeyedValues.decode(PackageInfo.Product.ProductType.LibraryType.self)
            self = .library(libraryType)
        case .test:
            self = .test
        case .executable:
            self = .executable
        case .plugin:
            self = .plugin
        }
    }
}
