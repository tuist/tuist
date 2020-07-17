import Foundation

public struct ScaleResponse<T: Decodable>: Decodable {
    public let status: String
    public let data: T

    public init(status: String, data: T) {
        self.status = status
        self.data = data
    }
}
