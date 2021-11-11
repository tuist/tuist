import Foundation

public struct CloudResponse<T: Decodable>: Decodable {
    public let status: String
    public let data: T

    public init(status: String, data: T) {
        self.status = status
        self.data = data
    }
}

public struct CloudEmptyResponse: Decodable {
    public init() {}
}
