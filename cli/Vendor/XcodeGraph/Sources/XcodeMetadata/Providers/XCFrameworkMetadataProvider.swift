import FileSystem
import Foundation
import Logging
import Mockable
import Path
import XcodeGraph

// MARK: - Provider Errors

public enum XCFrameworkMetadataProviderError: LocalizedError, Equatable {
    case xcframeworkNotFound(AbsolutePath)
    case missingRequiredFile(AbsolutePath)
    case supportedArchitectureReferencesNotFound(AbsolutePath)
    case fileTypeNotRecognised(file: RelativePath, frameworkName: String)

    // MARK: - FatalError

    public var errorDescription: String? {
        switch self {
        case let .xcframeworkNotFound(path):
            return "Couldn't find xcframework at \(path.pathString)"
        case let .missingRequiredFile(path):
            return
                "The .xcframework at path \(path.pathString) doesn't contain an Info.plist. It's possible that the .xcframework was not generated properly or that got corrupted. Please, double check with the author of the framework."
        case let .supportedArchitectureReferencesNotFound(path):
            return
                "Couldn't find any supported architecture references at \(path.pathString). It's possible that the .xcframework was not generated properly or that it got corrupted. Please, double check with the author of the framework."
        case let .fileTypeNotRecognised(file, frameworkName):
            return
                "The extension of the file `\(file)`, which was found while parsing the xcframework `\(frameworkName)`, is not supported."
        }
    }
}

// MARK: - Provider

@Mockable
public protocol XCFrameworkMetadataProviding: PrecompiledMetadataProviding {
    /// It returns the supported architectures of the binary at the given path.
    /// - Parameter binaryPath: Binary path.
    func architectures(binaryPath: AbsolutePath) throws -> [BinaryArchitecture]

    /// Return how other binaries should link the binary at the given path.
    /// - Parameter binaryPath: Path to the binary.
    func linking(binaryPath: AbsolutePath) throws -> BinaryLinking

    /// It uses 'dwarfdump' to dump the UUIDs of each architecture.
    /// The UUIDs allows us to know which .bcsymbolmap files belong to this binary.
    /// - Parameter binaryPath: Path to the binary.
    func uuids(binaryPath: AbsolutePath) throws -> Set<UUID>

    /// Loads all the metadata associated with an XCFramework at the specified path, and expected signature if signed
    /// - Note: This performs various shell calls and disk operations
    func loadMetadata(at path: AbsolutePath, expectedSignature: XCFrameworkSignature?, status: LinkingStatus) async throws
        -> XCFrameworkMetadata

    /// Returns the info.plist of the xcframework at the given path.
    /// - Parameter xcframeworkPath: Path to the xcframework.
    func infoPlist(xcframeworkPath: AbsolutePath) async throws -> XCFrameworkInfoPlist
}

// MARK: - Default Implementation

public final class XCFrameworkMetadataProvider: PrecompiledMetadataProvider,
    XCFrameworkMetadataProviding
{
    private let fileSystem: FileSysteming
    private let logger: Logger?

    public init(
        fileSystem: FileSysteming = FileSystem(),
        logger: Logger? = nil
    ) {
        self.fileSystem = fileSystem
        self.logger = logger
        super.init()
    }

    public func loadMetadata(
        at path: AbsolutePath,
        expectedSignature: XCFrameworkSignature?,
        status: LinkingStatus
    ) async throws -> XCFrameworkMetadata {
        guard try await fileSystem.exists(path) else {
            throw XCFrameworkMetadataProviderError.xcframeworkNotFound(path)
        }
        let infoPlist = try await infoPlist(xcframeworkPath: path)
        let linking = try await linking(
            xcframeworkPath: path,
            libraries: infoPlist.libraries
        )
        return XCFrameworkMetadata(
            path: path,
            infoPlist: infoPlist,
            linking: linking,
            mergeable: infoPlist.libraries.allSatisfy(\.mergeable),
            status: status,
            macroPath: try await macroPath(xcframeworkPath: path),
            swiftModules: try await fileSystem.glob(directory: path, include: ["**/*.swiftmodule"]).collect().sorted(),
            moduleMaps: try await fileSystem.glob(directory: path, include: ["**/*.modulemap"]).collect().sorted(),
            expectedSignature: expectedSignature
        )
    }

    /**
     An XCFramework that contains static frameworks that represent macros, those are frameworks with a Macros directory in them.
     We assume that the Swift Macros, which are command line executables, are fat binaries for both architectures supported by macOS:
     x86_64 and arm64.
     */
    public func macroPath(xcframeworkPath: AbsolutePath) async throws -> AbsolutePath? {
        guard let frameworkPath = try await fileSystem.glob(directory: xcframeworkPath, include: ["*/*.framework"])
            .collect()
            .sorted()
            .first
        else { return nil }
        guard let macroPath = try await fileSystem.glob(directory: frameworkPath, include: ["Macros/*"]).collect().first else {
            return nil
        }
        return try AbsolutePath(validating: macroPath.pathString)
    }

    public func infoPlist(xcframeworkPath: AbsolutePath) async throws -> XCFrameworkInfoPlist {
        let infoPlist = xcframeworkPath.appending(component: "Info.plist")
        guard try await fileSystem.exists(infoPlist) else {
            throw XCFrameworkMetadataProviderError.missingRequiredFile(infoPlist)
        }

        return try await fileSystem.readPlistFile(at: infoPlist)
    }

    private func linking(xcframeworkPath: AbsolutePath, libraries: [XCFrameworkInfoPlist.Library])
        async throws -> BinaryLinking
    {
        let archs: [BinaryArchitecture] = [.arm64, .x8664]

        for library in libraries {
            let hasValidArchitectures = !library.architectures.filter(archs.contains).isEmpty
            guard hasValidArchitectures,
                  let linking = try? await linking(for: library, xcframeworkPath: xcframeworkPath)
            else {
                continue
            }

            return linking
        }

        throw XCFrameworkMetadataProviderError.supportedArchitectureReferencesNotFound(
            xcframeworkPath
        )
    }

    private func linking(
        for library: XCFrameworkInfoPlist.Library,
        xcframeworkPath: AbsolutePath
    ) async throws -> BinaryLinking {
        let (binaryPath, linking): (AbsolutePath, BinaryLinking?)

        switch library.path.extension {
        case "framework":
            binaryPath = try AbsolutePath(
                validating: library.identifier, relativeTo: xcframeworkPath
            )
            .appending(try RelativePath(validating: library.path.pathString))
            .appending(component: library.path.basenameWithoutExt)
            linking = try? self.linking(binaryPath: binaryPath)
        case "a":
            binaryPath = try AbsolutePath(
                validating: library.identifier, relativeTo: xcframeworkPath
            )
            .appending(try RelativePath(validating: library.path.pathString))
            linking = .static
        case "dylib":
            binaryPath = try AbsolutePath(
                validating: library.identifier, relativeTo: xcframeworkPath
            )
            .appending(try RelativePath(validating: library.path.pathString))
            linking = .dynamic
        default:
            throw XCFrameworkMetadataProviderError.fileTypeNotRecognised(
                file: library.path,
                frameworkName: xcframeworkPath.basename
            )
        }

        guard try await fileSystem.exists(binaryPath), let linking else {
            // The missing slice relative to the XCFramework folder. e.g ios-x86_64-simulator/Alamofire.framework/Alamofire
            let relativeArchitectureBinaryPath = binaryPath.components.suffix(3).joined(
                separator: "/"
            )
            logger?
                .warning(
                    "\(xcframeworkPath.basename) is missing architecture \(relativeArchitectureBinaryPath) defined in the Info.plist"
                )
            throw XCFrameworkMetadataProviderError.supportedArchitectureReferencesNotFound(
                binaryPath
            )
        }

        return linking
    }
}
