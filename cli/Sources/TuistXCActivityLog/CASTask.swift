import Foundation

public struct CASTask: Equatable {
    public let nodeID: String
    public let checksum: String?
    public let size: Int?

    public init(nodeID: String, checksum: String?, size: Int?) {
        self.nodeID = nodeID
        self.checksum = checksum
        self.size = size
    }
}