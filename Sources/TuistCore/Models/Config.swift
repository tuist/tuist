import Basic
import Foundation
import TuistSupport

/// This model allows to configure Tuist.
public struct Config: Equatable, Hashable {
    /// Contains options related to the project generation.
    ///
    /// - xcodeProjectName: Name used for the Xcode project
    public enum GenerationOption: Hashable, Equatable {
        case xcodeProjectName(String)
    }

    /// Generation options.
    public let generationOptions: [GenerationOption]

    /// List of Xcode versions the project or set of projects is compatible with.
    public let compatibleXcodeVersions: CompatibleXcodeVersions

    /// Returns the default Tuist configuration.
    public static var `default`: Config {
        Config(compatibleXcodeVersions: .all, generationOptions: [])
    }

    /// Initializes the tuist cofiguration.
    ///
    /// - Parameters:
    ///   - compatibleXcodeVersions: List of Xcode versions the project or set of projects is compatible with.
    ///   - generationOptions: Generation options.
    public init(compatibleXcodeVersions: CompatibleXcodeVersions,
                generationOptions: [GenerationOption]) {
        self.compatibleXcodeVersions = compatibleXcodeVersions
        self.generationOptions = generationOptions
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(generationOptions)
    }
}
