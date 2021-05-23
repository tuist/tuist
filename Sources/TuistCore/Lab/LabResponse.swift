import Foundation

public struct LabResponse<T: Decodable>: Decodable {
    public let status: String
    public let data: T

    public init(status: String, data: T) {
        self.status = status
        self.data = data
    }
}
