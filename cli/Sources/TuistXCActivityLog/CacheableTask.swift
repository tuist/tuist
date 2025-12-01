import Foundation

public struct CacheableTask: Equatable {
    public enum CacheStatus: Equatable {
        case localHit
        case remoteHit
        case miss
    }

    public enum TaskType: Equatable {
        case swift
        case clang
    }

    public let key: String
    public let status: CacheStatus
    public let type: TaskType
    public let readDuration: TimeInterval?
    public let writeDuration: TimeInterval?
    public let description: String?
    public let nodeIDs: [String]

    public init(
        key: String,
        status: CacheStatus,
        type: TaskType,
        readDuration: TimeInterval? = nil,
        writeDuration: TimeInterval? = nil,
        description: String? = nil,
        nodeIDs: [String] = []
    ) {
        self.key = key
        self.status = status
        self.type = type
        self.readDuration = readDuration
        self.writeDuration = writeDuration
        self.description = description
        self.nodeIDs = nodeIDs
    }
}
