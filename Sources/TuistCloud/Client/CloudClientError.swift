import Foundation

enum CloudClientError: LocalizedError, Equatable {
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Unauthorized error"
        }
    }
}
