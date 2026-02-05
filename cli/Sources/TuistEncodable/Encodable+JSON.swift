import Foundation
import TSCBasic

extension Encodable {
    public func toJSON() throws -> JSON {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        return try JSON(data: data)
    }
}
