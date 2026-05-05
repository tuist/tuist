import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public enum RequestIDHeader {
    public static let name = "x-request-id"
}

extension HTTPRequest {
    public var requestID: String? {
        guard let requestIDHeaderName = HTTPField.Name(RequestIDHeader.name) else { return nil }
        return headerFields[requestIDHeaderName]
    }

    public mutating func addRequestIDHeader(_ requestID: String = UUID().uuidString) {
        guard let requestIDHeaderName = HTTPField.Name(RequestIDHeader.name) else { return }
        headerFields[requestIDHeaderName] = requestID
    }
}

extension URLRequest {
    public var requestID: String? {
        value(forHTTPHeaderField: RequestIDHeader.name)
    }

    public mutating func addRequestIDHeader(_ requestID: String = UUID().uuidString) {
        setValue(requestID, forHTTPHeaderField: RequestIDHeader.name)
    }
}

extension HTTPURLResponse {
    public var requestID: String? {
        value(forHTTPHeaderField: RequestIDHeader.name)
    }
}
