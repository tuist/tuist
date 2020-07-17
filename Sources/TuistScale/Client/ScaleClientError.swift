import Foundation

public enum ScaleClientError: LocalizedError, Equatable {
    case unauthorized

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Unauthorized error"
        }
    }
}
