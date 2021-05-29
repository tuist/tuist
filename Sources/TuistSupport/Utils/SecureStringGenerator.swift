import Foundation

enum SecureStringGeneratorError: FatalError {
    case unknownError

    var type: ErrorType {
        switch self {
        case .unknownError: return .bug
        }
    }

    var description: String {
        switch self {
        case .unknownError: return "Couldn't generate cryptographically secure secret."
        }
    }
}

public protocol SecureStringGenerating {
    func generate() throws -> String
}

public final class SecureStringGenerator: SecureStringGenerating {
    public init() {}

    public func generate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        guard result == errSecSuccess else {
            throw SecureStringGeneratorError.unknownError
        }

        return Data(bytes).base64EncodedString()
    }
}
