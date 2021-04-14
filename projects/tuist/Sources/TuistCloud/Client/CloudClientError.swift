import Foundation

public enum CloudClientError: LocalizedError, Equatable {
    case unauthorized

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Unauthorized error"
        }
    }
}
