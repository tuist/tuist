import Foundation

public enum CommandEventCacheHit: Codable, Equatable {
    case miss, local, remote
}
