import Foundation
import Path
import XcodeGraph
import XcodeProj

/// Defines errors that may occur when mapping package references.
enum PackageMappingError: Error, LocalizedError, Equatable {
    case missingRepositoryURL(packageName: String)

    var errorDescription: String? {
        switch self {
        case let .missingRepositoryURL(packageName):
            return "The repository URL is missing for the package: \(packageName)."
        }
    }
}

/// A protocol defining how to map remote and local Swift package references into `Package` models.
protocol XCPackageMapping {
    /// Maps a remote Swift package reference to a `Package`.
    ///
    /// - Parameter package: The remote package reference.
    /// - Returns: A `Package` representing the remote package.
    /// - Throws: `PackageMappingError.missingRepositoryURL` if the package has no repository URL.
    func map(package: XCRemoteSwiftPackageReference) throws -> Package

    /// Maps a local Swift package reference to a `Package`.
    ///
    /// - Parameters:
    ///   - package: The local Swift package reference.
    ///   - sourceDirectory: The project’s source directory used to resolve relative paths.
    /// - Returns: A `Package` representing the local package.
    /// - Throws: If the provided path is invalid and cannot be resolved.
    func map(package: XCLocalSwiftPackageReference, sourceDirectory: AbsolutePath) throws -> Package
}

/// A mapper that converts remote and local Swift package references into `Package` domain models.
struct XCPackageMapper: XCPackageMapping {
    func map(package: XCRemoteSwiftPackageReference) throws -> Package {
        guard let repositoryURL = package.repositoryURL else {
            let name = package.name ?? "Unknown Package"
            throw PackageMappingError.missingRepositoryURL(packageName: name)
        }
        let requirement = mapRequirement(package: package)
        return .remote(url: repositoryURL, requirement: requirement)
    }

    func map(package: XCLocalSwiftPackageReference, sourceDirectory: AbsolutePath) throws -> Package {
        let relativePath = try RelativePath(validating: package.relativePath)
        let path = sourceDirectory.appending(relativePath)
        return .local(path: path)
    }

    // MARK: - Private Helpers

    /// Determines the version requirement for a remote Swift package.
    private func mapRequirement(package: XCRemoteSwiftPackageReference) -> Requirement {
        guard let versionRequirement = package.versionRequirement else {
            // Default to an all-zero version if none is specified
            return .upToNextMajor("0.0.0")
        }

        switch versionRequirement {
        case let .upToNextMajorVersion(version):
            return .upToNextMajor(version)
        case let .upToNextMinorVersion(version):
            return .upToNextMinor(version)
        case let .exact(version):
            return .exact(version)
        case let .range(lowerBound, upperBound):
            return .range(from: lowerBound, to: upperBound)
        case let .branch(branch):
            return .branch(branch)
        case let .revision(revision):
            return .revision(revision)
        }
    }
}
