import Foundation

public enum RunCacheHit: Codable, Equatable {
    case miss, local, remote
}
