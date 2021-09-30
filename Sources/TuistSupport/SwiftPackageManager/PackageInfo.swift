import ProjectDescription
import TSCUtility

// MARK: - PackageInfo

/// The Swift Package Manager package information.
/// It decodes data encoded from Manifest.swift: https://github.com/apple/swift-package-manager/blob/06f9b30f4593940272f57f6284e5614d817d2f22/Sources/PackageModel/Manifest.swift#L372-L409
/// Fields not needed by tuist are commented out and not decoded at all.
public struct PackageInfo: Hashable {
    /// The products declared in the manifest.
    public let products: [Product]

    /// The targets declared in the manifest.
    public let targets: [Target]

    /// The declared platforms in the manifest.
    public let platforms: [Platform]

    /// The supported C language standard to use for compiling C sources in the package.
    public let cLanguageStandard: String?

    /// The supported C++ language standard to use for compiling C++ sources in the package.
    public let cxxLanguageStandard: String?

    /// The supported swift language standard to use for compiling Swift sources in the package.
    public let swiftLanguageVersions: [TSCUtility.Version]?

    // Ignored fields

    // /// The name of the package.
    // let name: String

    // /// The tools version declared in the manifest.
    // let toolsVersion: ToolsVersion

    // /// The pkg-config name of a system package.
    // let pkgConfig: String?

    // /// The system package providers of a system package.
    // let providers: [SystemPackageProviderDescription]?

    // /// The declared package dependencies.
    // let dependencies: [PackageDependencyDescription]

    // /// Whether kind of package this manifest is from.
    // let packageKind: PackageReference.Kind

    public init(
        products: [Product],
        targets: [Target],
        platforms: [Platform],
        cLanguageStandard: String?,
        cxxLanguageStandard: String?,
        swiftLanguageVersions: [TSCUtility.Version]?
    ) {
        self.products = products
        self.targets = targets
        self.platforms = platforms
        self.cLanguageStandard = cLanguageStandard
        self.cxxLanguageStandard = cxxLanguageStandard
        self.swiftLanguageVersions = swiftLanguageVersions
    }
}

// MARK: Platform

extension PackageInfo {
    public struct Platform: Decodable, Hashable {
        public let platformName: String
        public let version: String
        public let options: [String]

        public init(
            platformName: String,
            version: String,
            options: [String]
        ) {
            self.platformName = platformName
            self.version = version
            self.options = options
        }
    }
}

// MARK: PackageConditionDescription

extension PackageInfo {
    public struct PackageConditionDescription: Decodable, Hashable {
        public let platformNames: [String]
        public let config: String?

        public init(
            platformNames: [String],
            config: String?
        ) {
            self.platformNames = platformNames
            self.config = config
        }
    }
}

// MARK: - Product

extension PackageInfo {
    public struct Product: Decodable, Hashable {
        /// The name of the product.
        public let name: String

        /// The type of product to create.
        public let type: Product.ProductType

        /// The list of targets to combine to form the product.
        ///
        /// This is never empty, and is only the targets which are required to be in
        /// the product, but not necessarily their transitive dependencies.
        public let targets: [String]

        public init(
            name: String,
            type: Product.ProductType,
            targets: [String]
        ) {
            self.name = name
            self.type = type
            self.targets = targets
        }
    }
}

extension PackageInfo.Product {
    public enum ProductType: Hashable {
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

// MARK: - Target

extension PackageInfo {
    public struct Target: Decodable, Hashable {
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

        /// The custom headers path.
        public let publicHeadersPath: String?

        /// The type of target.
        public let type: TargetType

        /// The target-specific build settings declared in this target.
        public let settings: [TargetBuildSettingDescription.Setting]

        /// The binary target checksum.
        public let checksum: String?

        public init(
            name: String,
            path: String?,
            url: String?,
            sources: [String]?,
            resources: [Resource],
            exclude: [String],
            dependencies: [Dependency],
            publicHeadersPath: String?,
            type: TargetType,
            settings: [TargetBuildSettingDescription.Setting],
            checksum: String?
        ) {
            self.name = name
            self.path = path
            self.url = url
            self.sources = sources
            self.resources = resources
            self.exclude = exclude
            self.dependencies = dependencies
            self.publicHeadersPath = publicHeadersPath
            self.type = type
            self.settings = settings
            self.checksum = checksum
        }
    }
}

// MARK: Target.Dependency

extension PackageInfo.Target {
    /// A dependency of the target.
    public enum Dependency: Hashable {
        /// A dependency internal to the same package.
        case target(name: String, condition: PackageInfo.PackageConditionDescription?)

        /// A product from an external package.
        case product(name: String, package: String, condition: PackageInfo.PackageConditionDescription?)

        /// A dependency to be resolved by name.
        case byName(name: String, condition: PackageInfo.PackageConditionDescription?)
    }
}

// MARK: Target.Resource

extension PackageInfo.Target {
    public struct Resource: Decodable, Hashable {
        public enum Rule: String, Decodable, Hashable {
            case process
            case copy
        }

        public enum Localization: String, Decodable, Hashable {
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
    public enum TargetType: String, Hashable, Decodable {
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
        public enum Tool: String, Decodable, Hashable, CaseIterable {
            case c
            case cxx
            case swift
            case linker
        }

        /// The name of the build setting.
        public enum SettingName: String, Decodable, Hashable {
            case headerSearchPath
            case define
            case linkedLibrary
            case linkedFramework
            case unsafeFlags
        }

        /// An individual build setting.
        public struct Setting: Decodable, Hashable {
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

            public init(
                tool: Tool,
                name: SettingName,
                condition: PackageInfo.PackageConditionDescription?,
                value: [String]
            ) {
                self.tool = tool
                self.name = name
                self.condition = condition
                self.value = value
            }
        }
    }
}

// MARK: Decodable conformances

extension PackageInfo: Decodable {
    private enum CodingKeys: String, CodingKey {
        case products, targets, platforms, cLanguageStandard, cxxLanguageStandard, swiftLanguageVersions
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        products = try values.decode([Product].self, forKey: .products)
        targets = try values.decode([Target].self, forKey: .targets)
        platforms = try values.decode([Platform].self, forKey: .platforms)
        cLanguageStandard = try values.decodeIfPresent(String.self, forKey: .cLanguageStandard)
        cxxLanguageStandard = try values.decodeIfPresent(String.self, forKey: .cxxLanguageStandard)
        swiftLanguageVersions = try values
            .decodeIfPresent([String].self, forKey: .swiftLanguageVersions)?
            .compactMap { TSCUtility.Version(unformattedString: $0) }
    }
}

extension PackageInfo.Target.Dependency: Decodable {
    private enum CodingKeys: String, CodingKey {
        case target, product, byName
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = values.allKeys.first(where: values.contains) else {
            throw DecodingError
                .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
        }

        var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
        switch key {
        case .target:
            self = .target(
                name: try unkeyedValues.decode(String.self),
                condition: try unkeyedValues.decodeIfPresent(PackageInfo.PackageConditionDescription.self)
            )
        case .product:
            let first = try unkeyedValues.decode(String.self)
            self = .product(
                name: first,
                package: try unkeyedValues.decodeIfPresent(String.self) ?? first,
                condition: try unkeyedValues.decodeIfPresent(PackageInfo.PackageConditionDescription.self)
            )
        case .byName:
            self = .byName(
                name: try unkeyedValues.decode(String.self),
                condition: try unkeyedValues.decodeIfPresent(PackageInfo.PackageConditionDescription.self)
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
            throw DecodingError
                .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
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
