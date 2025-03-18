import Command
import CryptoKit
import FileSystem
import Foundation
import Path
import TSCBasic
import TuistSupport
import XcodeGraph

enum XCFrameworkSignatureProviderError: FatalError, Equatable {
    case codesignOutputMissing
    case certificateFileReadFailed
    case appleSignedXCFrameworkMissingDetails(teamIdentifier: String?, teamName: String?)

    var description: String {
        switch self {
            case .codesignOutputMissing:
            return "codesign finished, but no output file was found."
            case .certificateFileReadFailed:
                return "Failed to read certificate file."
            case let .appleSignedXCFrameworkMissingDetails(teamIdentifier, teamName):
            return "Apple signed XCFramework missing team identifier or name. teamIdentifier: \(teamIdentifier ?? "nil"), teamName: \(teamName ?? "nil")"
        }
    }
    
    var type: TuistSupport.ErrorType {
        switch self {
        case .codesignOutputMissing, .certificateFileReadFailed, .appleSignedXCFrameworkMissingDetails:
            return .abort
        }
    }
}

/// A provider that can verify the signature calculated from an XCFramework.
public struct XCFrameworkSignatureProvider {
    private let commandRunner: CommandRunning
    private let fileSystem: FileSysteming
    private let codesignController: CodesignController

    public init(
        commandRunner: CommandRunning = CommandRunner(),
        fileSystem: FileSysteming = FileSystem(),
        codesignController: CodesignController = CodesignController()
    ) {
        self.commandRunner = commandRunner
        self.fileSystem = fileSystem
        self.codesignController = codesignController
    }

    private static let signedByAppleString = "Authority=Apple Root CA"
    private static let teamNameRegExPattern = #"Authority=[^:]+?:\s*([^()]+)\s*\(([A-Z0-9]+)\)"#
    private static let teamIdentifierRegExPattern = #"TeamIdentifier=([A-Z0-9]+)"#

    /// Returns the signature of the XCFramework at the given `xcframeworkPath`.
    public func signature(of xcframeworkPath: Path.AbsolutePath) async throws -> XCFrameworkSignature {
        guard let output = await codesignController.codesignSignature(of: xcframeworkPath) else {
            return .notSigned
        }

        guard output.contains(Self.signedByAppleString) else {
            let fingerprint = try await extractFingerprint(from: xcframeworkPath)
            return .selfSigned(fingerprint: fingerprint)
        }

        let teamIdentifier = (try? RegEx(pattern: Self.teamIdentifierRegExPattern).matchGroups(in: output).first?.first)?.trimmingCharacters(in: .whitespaces)
        let teamName = (try? RegEx(pattern: Self.teamNameRegExPattern).matchGroups(in: output).first?.first)?.trimmingCharacters(in: .whitespaces)

        guard let teamIdentifier = teamIdentifier, let teamName = teamName else {
            throw XCFrameworkSignatureProviderError.appleSignedXCFrameworkMissingDetails(teamIdentifier: teamIdentifier, teamName: teamName)
        }

        return .signedByApple(teamIdentifier: teamIdentifier, teamName: teamName)
    }

    private func extractFingerprint(from xcframeworkPath: Path.AbsolutePath) async throws -> String {
        try await fileSystem.runInTemporaryDirectory(prefix: "xcframework-signature-extractor)") { temporaryPath in
            try await codesignController.codesignExtractSignature(of: xcframeworkPath, workingDirectory: temporaryPath)

            let certFile: Path.AbsolutePath = temporaryPath.appending(component: "codesign0")
            guard try await fileSystem.exists(certFile) else {
                throw XCFrameworkSignatureProviderError.codesignOutputMissing
            }

            guard let certificateFileData = try? Data(contentsOf: URL(fileURLWithPath: certFile.pathString)) else {
                throw XCFrameworkSignatureProviderError.certificateFileReadFailed
            }

            let hash = SHA256.hash(data: certificateFileData)
            let fingerprint = hash.compactMap { String(format: "%02X", $0) }.joined()

            return fingerprint
        }
    }
}
