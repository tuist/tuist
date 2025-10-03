import Foundation
import SWBUtil

public struct CASObject: CASObjectProtocol, Equatable, Sendable {
    public let data: ByteString
    public let refs: [DataID]

    public init(data: ByteString, refs: [DataID] = []) {
        self.data = data
        self.refs = refs
    }

    public init(data: Data, refs: [DataID] = []) {
        self.data = ByteString(data)
        self.refs = refs
    }

    public init(string: String, refs: [DataID] = []) {
        self.data = ByteString(Array(string.utf8))
        self.refs = refs
    }

    public var id: DataID {
        DataID(from: data)
    }
}