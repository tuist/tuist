import Foundation

/// A credential helper that follows the git credential helper pattern.
/// The helper is invoked as an external process that receives a request via stdin
/// and returns credentials via stdout.
public struct CredentialHelper: Sendable {
    public let executablePath: String

    public init(executablePath: String) {
        self.executablePath = executablePath
    }

    /// Request credentials from the helper for the given URL and project ID.
    ///
    /// The helper receives JSON via stdin:
    /// ```json
    /// {
    ///   "url": "https://cache.tuist.io",
    ///   "projectId": "my-project-123"
    /// }
    /// ```
    ///
    /// And should respond via stdout with:
    /// ```json
    /// {
    ///   "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
    /// }
    /// ```
    ///
    /// Or in case of error:
    /// ```json
    /// {
    ///   "error": "Not authenticated. Run 'tuist auth' first."
    /// }
    /// ```
    public func getCredential(url: URL, projectId: String?) async throws -> String {
        let request = CredentialRequest(
            url: url.absoluteString,
            projectId: projectId
        )

        let requestData = try JSONEncoder().encode(request)
        guard let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw CredentialHelperError.encodingFailed
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try await process.run()

        // Write request to stdin
        if let inputData = requestJSON.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(inputData)
            inputPipe.fileHandleForWriting.write("\n".data(using: .utf8)!)
        }
        try inputPipe.fileHandleForWriting.close()

        // Wait for completion
        process.waitUntilExit()

        // Read response from stdout
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw CredentialHelperError.helperFailed(exitCode: process.terminationStatus, message: errorMessage)
        }

        let response = try JSONDecoder().decode(CredentialResponse.self, from: outputData)

        if let error = response.error {
            throw CredentialHelperError.credentialError(error)
        }

        guard let token = response.token else {
            throw CredentialHelperError.missingToken
        }

        return token
    }
}

struct CredentialRequest: Codable {
    let url: String
    let projectId: String?
}

struct CredentialResponse: Codable {
    let token: String?
    let error: String?
}

public enum CredentialHelperError: Error, CustomStringConvertible {
    case encodingFailed
    case helperFailed(exitCode: Int32, message: String)
    case credentialError(String)
    case missingToken

    public var description: String {
        switch self {
        case .encodingFailed:
            return "Failed to encode credential request"
        case .helperFailed(let exitCode, let message):
            return "Credential helper exited with code \(exitCode): \(message)"
        case .credentialError(let message):
            return "Credential helper error: \(message)"
        case .missingToken:
            return "Credential helper response missing token"
        }
    }
}
