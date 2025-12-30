import Command
import CryptoKit
import FileSystem
import Foundation
import Path
import TSCBasic
import TuistSupport
import XcodeGraph

enum XCFrameworkSignatureProviderError: LocalizedError, Equatable {
    case codesignOutputMissing(_ certificateFilePath: Path.AbsolutePath)
    case certificateFileReadFailed(_ xcframeworkPath: Path.AbsolutePath)
    case appleCertificateSignedXCFrameworkMissingDetails(
        _ xcframeworkPath: Path.AbsolutePath,
        teamIdentifier: String?,
        teamName: String?
    )

    var errorDescription: String {
        switch self {
        case let .codesignOutputMissing(path):
            return "Couldn't find the codesign0 certificate for XCFramework at \(path)."
        case let .certificateFileReadFailed(path):
            return "Failed to read certificate file for XCFramework at \(path)."
        case let .appleCertificateSignedXCFrameworkMissingDetails(path, teamIdentifier, teamName):
            switch (teamIdentifier, teamName) {
            case (nil, .some):
                return "The framework at \(path) signed with an Apple certificate lacks the team identifier."
            case (.some, nil):
                return "The framework at \(path) signed with an Apple certificate lacks the team name."
            default:
                return "The framework at \(path) signed with an Apple certificate lacks the team identifier and name."
            }
        }
    }
}

/// A provider that can verify the signature calculated from an XCFramework.
public struct XCFrameworkSignatureProvider {
    private let commandRunner: CommandRunning
    private let fileSystem: FileSysteming
    private let codesignController: CodesignControlling

    public init(
        commandRunner: CommandRunning = CommandRunner(),
        fileSystem: FileSysteming = FileSystem(),
        codesignController: CodesignControlling = CodesignController()
    ) {
        self.commandRunner = commandRunner
        self.fileSystem = fileSystem
        self.codesignController = codesignController
    }

    private static let signedWithAppleCertificateString = "Authority=Apple Root CA"

    /// Regex to find team name in signature description. Examples:
    /// 1. Authority=iPhone Distribution: Tuist GmbH
    /// 2. Authority=Developer ID Application: Tuist GmbH (U6LC622NKF)
    private static let teamNameRegExPattern = #"Authority=[^:]+?:\s*([^()|^\n]+)\s*(\(([A-Z0-9]+)\))?"#

    /// Regex to find team id in signature description. Example
    /// TeamIdentifier=U6LC622NKF
    private static let teamIdentifierRegExPattern = #"TeamIdentifier=([A-Z0-9]+)"#

    /// Returns the signature of the XCFramework at the given `xcframeworkPath`.
    public func signature(of xcframeworkPath: Path.AbsolutePath) async throws -> XCFrameworkSignature {
        guard let output = try await codesignController.signature(of: xcframeworkPath) else {
            return .unsigned
        }

        guard output.contains(Self.signedWithAppleCertificateString) else {
            let fingerprint = try await extractFingerprint(from: xcframeworkPath)
            return .selfSigned(fingerprint: fingerprint)
        }

        let teamIdentifier = (try? RegEx(pattern: Self.teamIdentifierRegExPattern).matchGroups(in: output).first?.first)?
            .trimmingCharacters(in: .whitespaces)
        let teamName = (try? RegEx(pattern: Self.teamNameRegExPattern).matchGroups(in: output).first?.first)?
            .trimmingCharacters(in: .whitespaces)

        guard let teamIdentifier, let teamName else {
            throw XCFrameworkSignatureProviderError.appleCertificateSignedXCFrameworkMissingDetails(
                xcframeworkPath,
                teamIdentifier: teamIdentifier,
                teamName: teamName
            )
        }

        return .signedWithAppleCertificate(teamIdentifier: teamIdentifier, teamName: teamName)
    }

    private func extractFingerprint(from xcframeworkPath: Path.AbsolutePath) async throws -> String {
        try await fileSystem.runInTemporaryDirectory(prefix: "xcframework-signature-extractor)") { temporaryPath in
            try await codesignController.extractSignature(of: xcframeworkPath, into: temporaryPath)

            let certFile = temporaryPath.appending(component: "codesign0")
            guard try await fileSystem.exists(certFile) else {
                throw XCFrameworkSignatureProviderError.codesignOutputMissing(certFile)
            }

            guard let certificateFileData = try? await fileSystem.readFile(at: certFile) else {
                throw XCFrameworkSignatureProviderError.certificateFileReadFailed(xcframeworkPath)
            }

            let hash = SHA256.hash(data: certificateFileData)
            let fingerprint = hash.compactMap { String(format: "%02X", $0) }.joined()

            return fingerprint
        }
    }
}
