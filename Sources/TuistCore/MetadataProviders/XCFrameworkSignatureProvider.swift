import Command
import CryptoKit
import FileSystem
import Foundation
import Path
import TSCBasic
import TuistSupport
import XcodeGraph

enum XCFrameworkSignatureProviderError: FatalError, Equatable {
    case codesignRunFailed(underlyingError: Error)
    case codesignOutputMissing
    case certificateFileReadFailed
    case appleSignedXCFrameworkMissingDetails(teamIdentifier: String?, teamName: String?)

    var description: String {
        switch self {
            case let .codesignRunFailed(underlyingError):
                return "Failed to run codesign command with error: \(underlyingError)"
            case .codesignOutputMissing:
            return "codesign finished, but no output file was found."
            case .certificateFileReadFailed:
                return "Failed to read certificate file."
            case let .appleSignedXCFrameworkMissingDetails(teamIdentifier, teamName):
            return "Apple signed XCFramework missing team identifier or name. teamIdentifier: \(teamIdentifier ?? "nil"), teamName: \(teamName ?? "nil")"
        }
    }

    static func == (lhs: XCFrameworkSignatureProviderError, rhs: XCFrameworkSignatureProviderError) -> Bool {
        switch (lhs, rhs) {
            case let (.codesignRunFailed(lhsUnderlyingError), .codesignRunFailed(rhsUnderlyingError)):
                return lhsUnderlyingError.localizedDescription == rhsUnderlyingError.localizedDescription
            case (.codesignOutputMissing, .codesignOutputMissing):
                return true
            case (.certificateFileReadFailed, .certificateFileReadFailed):
                return true
            case let (.appleSignedXCFrameworkMissingDetails(lhsTeamIdentifier, lhsTeamName), .appleSignedXCFrameworkMissingDetails(rhsTeamIdentifier, rhsTeamName)):
                return lhsTeamIdentifier == rhsTeamIdentifier && lhsTeamName == rhsTeamName
            default:
                return false
        }
    }

    var type: TuistSupport.ErrorType {
        switch self {
        case .codesignRunFailed, .codesignOutputMissing, .certificateFileReadFailed, .appleSignedXCFrameworkMissingDetails:
            return .abort
        }
    }
}


/// Actual signature type for XCFramework, calculated from the XCFramework.
/// Can be used to verify the authenticity of the XCFramework against the original (expected) signature.
public enum XCFrameworkSignatureType: Equatable {
    /// The XCFramework is not signed.
    case notSigned

    /// The XCFramework is signed with an Apple Development certificate.
    case signedByApple(teamIdentifier: String, teamName: String)

    /// The XCFramework is signed by a self issued code signing identity.
    case selfSigned(fingerprint: String)

    /// `true` iff the given signature is equal to the original signature.
    public func isEqualTo(originalSignature: XCFrameworkOriginalSignatureType) -> Bool {
        switch (self, originalSignature) {
            case (.notSigned, .notSigned):
                return true
            case (.signedByApple(let teamIdentifier, let teamName),
                  .signedByApple(let originalTeamIdentifier, let originalTeamName)):
                return teamIdentifier == originalTeamIdentifier && teamName == originalTeamName
            case (.selfSigned(let fingerprint), .selfSigned(let originalFingerprint)):
                return fingerprint == originalFingerprint
            default:
                return false
        }
    }
}

/// A provider that can verify the signature calculated from an XCFramework.
public struct XCFrameworkSignatureProvider {
    private let commandRunner: CommandRunning
    private let fileSystem: FileSysteming

    public init(
        commandRunner: CommandRunning = CommandRunner(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.commandRunner = commandRunner
        self.fileSystem = fileSystem
    }

    private static let signedByAppleString = "Authority=Apple Root CA"
    private static let teamNameRegExPattern = #"Authority=[^:]+?:\s*([^()]+)\s*\(([A-Z0-9]+)\)"#
    private static let teamIdentifierRegExPattern = #"TeamIdentifier=([A-Z0-9]+)"#

    /// Returns the type of the signature of the XCFramework at the given `xcframeworkPath`.
    func signingType(of xcframeworkPath: Path.AbsolutePath) async throws -> XCFrameworkSignatureType {
        guard let output = await codesignSignature(of: xcframeworkPath) else {
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

    private func codesignSignature(of xcframeworkPath: Path.AbsolutePath) async -> String? {
        do {
            return try await commandRunner.run(
                arguments: [
                    "/usr/bin/codesign",
                    "-dvv",
                    xcframeworkPath.pathString
                ]
            )
            .concatenatedString()

        } catch {
            return nil
        }
    }

    private func extractFingerprint(from xcframeworkPath: Path.AbsolutePath) async throws -> String {
        try await fileSystem.runInTemporaryDirectory(prefix: "xcframework-signature-extractor)") { temporaryPath in
            do {
                _ = try await commandRunner.run(
                    arguments: [
                        "/usr/bin/codesign",
                        "-d",
                        "--extract-certificates",
                        xcframeworkPath.pathString
                    ],
                    workingDirectory: temporaryPath
                )
                .awaitCompletion()
            } catch let error {
                throw XCFrameworkSignatureProviderError.codesignRunFailed(underlyingError: error)
            }

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
