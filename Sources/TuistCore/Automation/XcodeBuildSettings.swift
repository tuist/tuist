import Foundation
import TSCBasic

public struct XcodeBuildSettings {
    public typealias DictionaryType = [String: String]
    private let settings: DictionaryType

    /// The target to which these settings apply.
    public let target: String

    /// Build configuration.
    public let configuration: String

    public init(
        _ settings: DictionaryType,
        target: String,
        configuration: String
    ) {
        self.settings = settings
        self.target = target
        self.configuration = configuration
    }

    /// The relative path (from the build folder) to the built executable.
    public var executablePath: String? {
        settings["EXECUTABLE_PATH"]
    }

    /// The name of the built product's wrapper bundle.
    public var wrapperName: String? {
        settings["WRAPPER_NAME"]
    }

    /// Whether bitcode is enabled.
    public var bitcodeEnabled: Bool {
        settings["BITCODE_ENABLED"] == "YES"
    }

    /// Code signing identity.
    public var codeSigningIdentity: String? {
        settings["CODE_SIGN_IDENTITY"]
    }

    /// Whether ad hoc code signing is allowed.
    public var adHocCodeSigningAllowed: Bool {
        settings["AD_HOC_CODE_SIGNING_ALLOWED"] == "YES"
    }

    /// The path to the project that contains the current target.
    public var projectPath: String? {
        settings["PROJECT_FILE_PATH"]
    }

    /// The target build dir.
    public var targetBuildDirectory: String? {
        settings["TARGET_BUILD_DIR"]
    }

    /// The target product name.
    public var productName: String? {
        settings["PRODUCT_NAME"]
    }

    /// The target swift version.
    public var swiftVersion: String? {
        settings["SWIFT_VERSION"]
    }

    /// The bundle identifier for the product.
    public var productBundleIdentifier: String? {
        settings["PRODUCT_BUNDLE_IDENTIFIER"]
    }
}

extension XcodeBuildSettings: CustomStringConvertible {
    public var description: String {
        "Build settings for target \(target) and configuration \(configuration):\n\(settings.map { "\($0)=\($1)" }.joined(separator: "\n"))"
    }
}

extension XcodeBuildSettings: Collection {
    // Required nested types, that tell Swift what our collection contains
    public typealias Index = DictionaryType.Index
    public typealias Element = DictionaryType.Element

    // The upper and lower bounds of the collection, used in iterations
    public var startIndex: Index { settings.startIndex }
    public var endIndex: Index { settings.endIndex }

    // Required subscript, based on a dictionary index
    public subscript(index: Index) -> Iterator.Element { settings[index] }

    // Method that returns the next index when iterating
    public func index(after i: Index) -> Index {
        settings.index(after: i)
    }
}
