import Foundation
import TuistLogging

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

public struct SecureStringGenerator: SecureStringGenerating {
    public init() {}

    public func generate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        #if canImport(Darwin)
            let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            guard result == errSecSuccess else {
                throw SecureStringGeneratorError.unknownError
            }
        #else
            for i in 0 ..< bytes.count {
                bytes[i] = UInt8.random(in: 0 ... 255)
            }
        #endif
        return Data(bytes).base64EncodedString()
    }
}
