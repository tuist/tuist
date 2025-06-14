import Foundation
import Mockable
import TuistCore
import XcodeGraph

@Mockable
public protocol CoreDataModelsContentHashing {
    func hash(coreDataModels: [CoreDataModel]) async throws -> String
}

/// `CoreDataModelsContentHasher`
/// is responsible for computing a unique hash that identifies a list of CoreData models
public struct CoreDataModelsContentHasher: CoreDataModelsContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - CoreDataModelsContentHashing

    public func hash(coreDataModels: [CoreDataModel]) async throws -> String {
        var stringsToHash: [String] = []
        for cdModel in coreDataModels {
            let contentHash = try await contentHasher.hash(path: cdModel.path)
            let currentVersionHash = try contentHasher.hash([cdModel.currentVersion])
            let cdModelHash = try contentHasher.hash([contentHash, currentVersionHash])
            let versionsHash = try await contentHasher
                .hash(try cdModel.versions.sorted().concurrentMap { try await contentHasher.hash(path: $0) })
            stringsToHash.append(cdModelHash)
            stringsToHash.append(versionsHash)
        }
        return try contentHasher.hash(stringsToHash)
    }
}
