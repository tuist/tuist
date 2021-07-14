// MARK: - PackageInfo

/// The Swift Package Manager package information.
/// It decodes data encoded from Manifest.swift: https://github.com/apple/swift-package-manager/blob/06f9b30f4593940272f57f6284e5614d817d2f22/Sources/PackageModel/Manifest.swift#L372-L409
/// Fields not needed by tuist are commented out and not decoded at all.
public struct PackageInfo: Decodable, Equatable {
    /// The products declared in the manifest.
    let products: [Product]

    /// The targets declared in the manifest.
    let targets: [Target]

    /// The declared platforms in the manifest.
    let platforms: [Platform]

    // Ignored fields

    // /// The name of the package.
    // let name: String

    // /// The tools version declared in the manifest.
    // let toolsVersion: ToolsVersion

    // /// The pkg-config name of a system package.
    // let pkgConfig: String?

    // /// The system package providers of a system package.
    // let providers: [SystemPackageProviderDescription]?

    // /// The C language standard flag.
    // let cLanguageStandard: String?

    // /// The C++ language standard flag.
    // let cxxLanguageStandard: String?

    // /// The supported Swift language versions of the package.
    // let swiftLanguageVersions: [SwiftLanguageVersion]?

    // /// The declared package dependencies.
    // let dependencies: [PackageDependencyDescription]

    // /// Whether kind of package this manifest is from.
    // let packageKind: PackageReference.Kind

    init(products: [Product], targets: [Target], platforms: [Platform]) {
        self.products = products
        self.targets = targets
        self.platforms = platforms
    }
}

// MARK: Platform

extension PackageInfo {
    struct Platform: Decodable, Equatable {
        let platformName: String
        let version: String
        let options: [String]
    }
}

// MARK: PackageConditionDescription

extension PackageInfo {
    struct PackageConditionDescription: Decodable, Equatable {
        let platformNames: [String]
        let config: String?
    }
}

// MARK: - Product

extension PackageInfo {
    struct Product: Decodable, Hashable {
        /// The name of the product.
        let name: String

        /// The type of product to create.
        let type: Product.ProductType

        /// The list of targets to combine to form the product.
        ///
        /// This is never empty, and is only the targets which are required to be in
        /// the product, but not necessarily their transitive dependencies.
        let targets: [String]
    }
}

extension PackageInfo.Product {
    enum ProductType: Hashable {
        /// The type of library.
        enum LibraryType: String, Codable {
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
    struct Target: Decodable, Equatable {
        /// The name of the target.
        let name: String

        /// The custom path of the target.
        let path: String?

        /// The url of the binary target artifact.
        let url: String?

        /// The custom sources of the target.
        let sources: [String]?

        /// The explicitly declared resources of the target.
        let resources: [Resource]

        /// The exclude patterns.
        let exclude: [String]

        /// The declared target dependencies.
        let dependencies: [Dependency]

        /// The custom headers path.
        let publicHeadersPath: String?

        /// The type of target.
        let type: TargetType

        /// The target-specific build settings declared in this target.
        let settings: [TargetBuildSettingDescription.Setting]

        /// The binary target checksum.
        let checksum: String?
    }
}

// MARK: Target.Dependency

extension PackageInfo.Target {
    /// A dependency of the target.
    enum Dependency: Equatable {
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
    struct Resource: Decodable, Equatable {
        enum Rule: String, Decodable, Equatable {
            case process
            case copy
        }

        enum Localization: String, Decodable, Equatable {
            case `default`
            case base
        }

        /// The rule for the resource.
        let rule: Rule

        /// The path of the resource.
        let path: String

        /// The explicit localization of the resource.
        let localization: Localization?

        init(rule: Rule, path: String, localization: Localization? = nil) {
            self.rule = rule
            self.path = path
            self.localization = localization
        }
    }
}

// MARK: Target.TargetType

extension PackageInfo.Target {
    enum TargetType: String, Equatable, Decodable {
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
    enum TargetBuildSettingDescription {
        /// The tool for which a build setting is declared.
        enum Tool: String, Decodable, Equatable, CaseIterable {
            case c
            case cxx
            case swift
            case linker
        }

        /// The name of the build setting.
        enum SettingName: String, Decodable, Equatable {
            case headerSearchPath
            case define
            case linkedLibrary
            case linkedFramework
            case unsafeFlags
        }

        /// An individual build setting.
        struct Setting: Decodable, Equatable {
            /// The tool associated with this setting.
            let tool: Tool

            /// The name of the setting.
            let name: SettingName

            /// The condition at which the setting should be applied.
            let condition: PackageInfo.PackageConditionDescription?

            /// The value of the setting.
            ///
            /// This is kind of like an "untyped" value since the length
            /// of the array will depend on the setting type.
            let value: [String]
        }
    }
}

// MARK: Decodable conformances

extension PackageInfo.Target.Dependency: Decodable {
    private enum CodingKeys: String, CodingKey {
        case target, product, byName
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = values.allKeys.first(where: values.contains) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
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

    init(from decoder: Decoder) throws {
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
