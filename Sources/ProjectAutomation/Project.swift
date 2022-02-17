import Foundation

/// The structure defining the output schema of a Xcode project.
public struct Project: Codable, Equatable {
    /// The name of the project.
    public let name: String

    /// The absolute path of the project.
    public let path: String

    /// Indicates whether the project is imported through `Dependencies.swift`.
    public let isExternal: Bool

    /// The Swift packages that this project depends on.
    public let packages: [Package]

    /// The targets this project produces.
    public let targets: [Target]

    /// The schemes available to this project.
    public let schemes: [Scheme]

    public init(
        name: String,
        path: String,
        isExternal: Bool,
        packages: [Package] = [Package](),
        targets: [Target] = [Target](),
        schemes: [Scheme] = [Scheme]()
    ) {
        self.name = name
        self.path = path
        self.isExternal = isExternal
        self.packages = packages
        self.targets = targets
        self.schemes = schemes
    }
}
