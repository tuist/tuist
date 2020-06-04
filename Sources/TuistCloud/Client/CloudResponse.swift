import Foundation

public struct CloudResponse<T: Decodable>: Decodable {
    public let status: String
    public let data: T
}
