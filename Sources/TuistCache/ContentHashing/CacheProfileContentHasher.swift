import Foundation
import TuistCore
import TuistGraph

public protocol CacheProfileContentHashing {
    func hash(cacheProfile: TuistGraph.Cache.Profile) throws -> String
}

/// `CacheProfileContentHasher`
/// is responsible for computing a unique hash that identifies a caching profile
public final class CacheProfileContentHasher: CacheProfileContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - CacheProfileContentHashing

    public func hash(cacheProfile: TuistGraph.Cache.Profile) throws -> String {
        var stringsToHash = [cacheProfile.name, cacheProfile.configuration]
        if let device = cacheProfile.device {
            stringsToHash.append(device)
        }
        if let os = cacheProfile.os {
            stringsToHash.append(os.description)
        }
        return try contentHasher.hash(stringsToHash)
    }
}
