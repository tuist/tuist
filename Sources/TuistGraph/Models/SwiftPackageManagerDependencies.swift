import Foundation

/// Contains the description of a dependency that can be installed using Swift Package Manager.
public struct SwiftPackageManagerDependencies: Equatable {
    /// List of packages that will be installed using Swift Package Manager.
    public let packages: [Package]

    /// Initializes a new `SwiftPackageManagerDependencies` instance.
    /// - Parameter packages: List of packages that will be installed using Swift Package Manager.
    public init(_ packages: [Package]) {
        self.packages = packages
    }
    
    /// Returns `Package.swift` representation.
    ///
    /// **NOTE** It is a temorary solution until Apple resolves: https://forums.swift.org/t/pitch-package-editor-commands/42224
    public func stringValue() -> String {
        """
        // swift-tools-version:5.3

        import PackageDescription

        let package = Package(
            name: "PackageName",
            dependencies: [
                \(packages.map { $0.stringValue + "," }.joined(separator: "\n        "))
            ]
        )
        """
    }
}

// MARK: - Package.stringValue()

private extension Package {
    /// Returns `Package.swift` representation.
    var stringValue: String {
        switch self {
        case let .local(path):
            return #".package(path: "\#(path)")"#
        case let .remote(url, requirement):
            return #".package(url: "\#(url)", \#(requirement.stringValue))"#
        }
    }
}

// MARK: - Requirement.stringValue()

private extension Requirement {
    /// Returns `Package.swift` representation.
    var stringValue: String {
        switch self {
        case let .exact(version):
            return #".exact("\#(version)")"#
        case let .upToNextMajor(version):
            return #".upToNextMajor(from: "\#(version)")"#
        case let .upToNextMinor(version):
            return #".upToNextMinor(from: "\#(version)")"#
        case let .branch(branch):
            return #".branch("\#(branch)")"#
        case let .revision(revision):
            return #".revision("\#(revision)")"#
        case let .range(from, to):
            return #""\#(from)"..<"\#(to)""#
        }
    }
}
