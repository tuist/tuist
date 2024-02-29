import ProjectDescription
import TSCBasic
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

    /// The name of the package.
    public let name: String

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
        name: String,
        products: [Product],
        targets: [Target],
        platforms: [Platform],
        cLanguageStandard: String?,
        cxxLanguageStandard: String?,
        swiftLanguageVersions: [TSCUtility.Version]?
    ) {
        self.name = name
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
    public struct Platform: Codable, Hashable {
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

        public var platform: PackagePlatform? {
            PackagePlatform(rawValue: platformName)
        }
    }
}

// MARK: PackageConditionDescription

extension PackageInfo {
    public struct PackageConditionDescription: Codable, Hashable {
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
    public struct Product: Codable, Hashable {
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
    public struct Target: Codable, Hashable {
        private enum CodingKeys: String, CodingKey {
            case name, path, url, sources, packageAccess, resources, exclude, dependencies, publicHeadersPath, type, settings,
                 checksum
        }

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

        /// If true, access to package declarations from other targets in the package is allowed.
        public let packageAccess: Bool

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
            checksum: String?,
            packageAccess: Bool = false
        ) {
            self.name = name
            self.path = path
            self.url = url
            self.sources = sources
            self.packageAccess = packageAccess
            self.resources = resources
            self.exclude = exclude
            self.dependencies = dependencies
            self.publicHeadersPath = publicHeadersPath
            self.type = type
            self.settings = settings
            self.checksum = checksum
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            path = try container.decodeIfPresent(String.self, forKey: .path)
            url = try container.decodeIfPresent(String.self, forKey: .url)
            sources = try container.decodeIfPresent([String].self, forKey: .sources)
            packageAccess = try container.decodeIfPresent(Bool.self, forKey: .packageAccess) ?? false
            resources = try container.decode([Resource].self, forKey: .resources)
            exclude = try container.decode([String].self, forKey: .exclude)
            dependencies = try container.decode([Dependency].self, forKey: .dependencies)
            publicHeadersPath = try container.decodeIfPresent(String.self, forKey: .publicHeadersPath)
            type = try container.decode(TargetType.self, forKey: .type)
            settings = try container.decode([TargetBuildSettingDescription.Setting].self, forKey: .settings)
            checksum = try container.decodeIfPresent(String.self, forKey: .checksum)
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
        case product(
            name: String,
            package: String,
            moduleAliases: [String: String]?,
            condition: PackageInfo.PackageConditionDescription?
        )

        /// A dependency to be resolved by name.
        case byName(name: String, condition: PackageInfo.PackageConditionDescription?)
    }
}

// MARK: Target.Resource

extension PackageInfo.Target {
    public struct Resource: Codable, Hashable {
        public enum Rule: String, Codable, Hashable {
            case process
            case copy

            public init(from decoder: Decoder) throws {
                // Xcode 14 format
                enum RuleXcode14: Codable, Equatable {
                    case process(localization: String?)
                    case copy
                }

                if let kind = try? RuleXcode14(from: decoder) {
                    switch kind {
                    case .process:
                        self = .process
                    case .copy:
                        self = .copy
                    }
                } else if let singleValue = try? decoder.singleValueContainer().decode(String.self) {
                    switch singleValue {
                    case "process":
                        self = .process
                    case "copy":
                        self = .copy
                    default:
                        throw DecodingError
                            .dataCorrupted(.init(
                                codingPath: decoder.codingPath,
                                debugDescription: "Invalid value for Resource.Rule: \(singleValue)"
                            ))
                    }
                } else {
                    throw DecodingError
                        .dataCorrupted(.init(
                            codingPath: decoder.codingPath,
                            debugDescription: "Invalid content for Resource decoder"
                        ))
                }
            }
        }

        public enum Localization: String, Codable, Hashable {
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
    public enum TargetType: String, Hashable, Codable {
        case regular
        case executable
        case test
        case system
        case binary
        case plugin
        case macro
    }
}

// MARK: Target.TargetBuildSettingDescription

extension PackageInfo.Target {
    /// A namespace for target-specific build settings.
    public enum TargetBuildSettingDescription {
        /// The tool for which a build setting is declared.
        public enum Tool: String, Codable, Hashable, CaseIterable {
            case c
            case cxx
            case swift
            case linker
        }

        /// The name of the build setting.
        public enum SettingName: String, Codable, Hashable {
            case headerSearchPath
            case define
            case linkedLibrary
            case linkedFramework
            case unsafeFlags
            case enableUpcomingFeature
            case enableExperimentalFeature
        }

        /// An individual build setting.
        public struct Setting: Codable, Hashable {
            /// The tool associated with this setting.
            public let tool: Tool

            /// The name of the setting.
            public let name: SettingName

            /// The condition at which the setting should be applied.
            public let condition: PackageInfo.PackageConditionDescription?

            public var hasConditions: Bool {
                condition != nil || condition?.platformNames.isEmpty == true
            }

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

            private enum CodingKeys: String, CodingKey {
                case tool, name, condition, value, kind
            }

            // Xcode 14 format
            private enum Kind: Codable, Equatable {
                case headerSearchPath(String)
                case define(String)
                case linkedLibrary(String)
                case linkedFramework(String)
                case unsafeFlags([String])
                case enableUpcomingFeature(String)
                case enableExperimentalFeature(String)
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)

                tool = try container.decode(Tool.self, forKey: .tool)
                condition = try container.decodeIfPresent(PackageInfo.PackageConditionDescription.self, forKey: .condition)
                if let kind = try? container.decode(Kind.self, forKey: .kind) {
                    switch kind {
                    case let .headerSearchPath(value):
                        name = .headerSearchPath
                        self.value = [value]
                    case let .define(value):
                        name = .define
                        self.value = [value]
                    case let .linkedLibrary(value):
                        name = .linkedLibrary
                        self.value = [value]
                    case let .linkedFramework(value):
                        name = .linkedFramework
                        self.value = [value]
                    case let .unsafeFlags(value):
                        name = .unsafeFlags
                        self.value = value
                    case let .enableUpcomingFeature(value):
                        name = .enableUpcomingFeature
                        self.value = [value]
                    case let .enableExperimentalFeature(value):
                        name = .enableExperimentalFeature
                        self.value = [value]
                    }
                } else {
                    name = try container.decode(SettingName.self, forKey: .name)
                    value = try container.decode([String].self, forKey: .value)
                }
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)

                try container.encode(tool, forKey: .tool)
                try container.encodeIfPresent(condition, forKey: .condition)
                switch name {
                case .headerSearchPath:
                    try container.encode(Kind.headerSearchPath(value.first!), forKey: .kind)
                case .define:
                    try container.encode(Kind.define(value.first!), forKey: .kind)
                case .linkedLibrary:
                    try container.encode(Kind.linkedLibrary(value.first!), forKey: .kind)
                case .linkedFramework:
                    try container.encode(Kind.linkedFramework(value.first!), forKey: .kind)
                case .unsafeFlags:
                    try container.encode(Kind.unsafeFlags(value), forKey: .kind)
                case .enableUpcomingFeature:
                    try container.encode(Kind.enableUpcomingFeature(value.first!), forKey: .kind)
                case .enableExperimentalFeature:
                    try container.encode(Kind.enableExperimentalFeature(value.first!), forKey: .kind)
                }
            }
        }
    }
}

// MARK: Codable conformances

extension PackageInfo: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, products, targets, platforms, cLanguageStandard, cxxLanguageStandard, swiftLanguageVersions
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
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

extension PackageInfo.Target.Dependency: Codable {
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
                moduleAliases: try unkeyedValues.decodeIfPresent([String: String].self),
                condition: try unkeyedValues.decodeIfPresent(PackageInfo.PackageConditionDescription.self)
            )
        case .byName:
            self = .byName(
                name: try unkeyedValues.decode(String.self),
                condition: try unkeyedValues.decodeIfPresent(PackageInfo.PackageConditionDescription.self)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .byName(name: name, condition: condition):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .byName)
            try unkeyedContainer.encode(name)
            if let condition {
                try unkeyedContainer.encode(condition)
            }
        case let .product(name: name, package: package, moduleAliases: moduleAliases, condition: condition):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .product)
            try unkeyedContainer.encode(name)
            try unkeyedContainer.encode(package)
            try unkeyedContainer.encode(moduleAliases)
            try unkeyedContainer.encode(condition)
        case let .target(name: name, condition: condition):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .target)
            try unkeyedContainer.encode(name)
            if let condition {
                try unkeyedContainer.encode(condition)
            }
        }
    }
}

extension PackageInfo.Product.ProductType: Codable {
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

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .executable:
            try container.encode(CodingKeys.executable.rawValue, forKey: .executable)
        case .plugin:
            try container.encode(CodingKeys.plugin.rawValue, forKey: .plugin)
        case .test:
            try container.encode(CodingKeys.test.rawValue, forKey: .test)
        case let .library(libraryType):
            var nestedContainer = container.nestedUnkeyedContainer(forKey: .library)
            try nestedContainer.encode(libraryType)
        }
    }
}

extension PackageInfo.Target.TargetType {
    /// Defines if target may have a public headers path
    /// Based on preconditions in https://github.com/apple/swift-package-manager/blob/main/Sources/PackageDescription/Target.swift
    public var supportsPublicHeaderPath: Bool {
        switch self {
        case .regular, .executable, .test:
            return true
        case .system, .binary, .plugin, .macro:
            return false
        }
    }

    /// Defines if target may have source files
    /// Based on preconditions in https://github.com/apple/swift-package-manager/blob/main/Sources/PackageDescription/Target.swift
    public var supportsSources: Bool {
        switch self {
        case .regular, .executable, .test, .plugin, .macro:
            return true
        case .system, .binary:
            return false
        }
    }

    /// Defines if target may have resource files
    /// Based on preconditions in https://github.com/apple/swift-package-manager/blob/main/Sources/PackageDescription/Target.swift
    public var supportsResources: Bool {
        switch self {
        case .regular, .executable, .test:
            return true
        case .system, .binary, .plugin, .macro:
            return false
        }
    }

    /// Defines if target may have other dependencies
    /// Based on preconditions in https://github.com/apple/swift-package-manager/blob/main/Sources/PackageDescription/Target.swift
    public var supportsDependencies: Bool {
        switch self {
        case .regular, .executable, .test, .plugin, .macro:
            return true
        case .system, .binary:
            return false
        }
    }

    /// Defines if target supports C, CXX, Swift or linker settings
    /// Based on preconditions in https://github.com/apple/swift-package-manager/blob/main/Sources/PackageDescription/Target.swift
    public var supportsCustomSettings: Bool {
        switch self {
        case .regular, .executable, .test:
            return true
        case .system, .binary, .plugin, .macro:
            return false
        }
    }
}
