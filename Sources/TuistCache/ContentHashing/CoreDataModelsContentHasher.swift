import Foundation
import TuistCore
import TuistGraph

public protocol CoreDataModelsContentHashing {
    func hash(coreDataModels: [CoreDataModel]) throws -> String
}

/// `CoreDataModelsContentHasher`
/// is responsible for computing a unique hash that identifies a list of CoreData models
public final class CoreDataModelsContentHasher: CoreDataModelsContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - CoreDataModelsContentHashing

    public func hash(coreDataModels: [CoreDataModel]) throws -> String {
        var stringsToHash: [String] = []
        for cdModel in coreDataModels {
            let contentHash = try contentHasher.hash(path: cdModel.path)
            let currentVersionHash = try contentHasher.hash([cdModel.currentVersion])
            let cdModelHash = try contentHasher.hash([contentHash, currentVersionHash])
            let versionsHash = try contentHasher.hash(cdModel.versions.map(\.pathString))
            stringsToHash.append(cdModelHash)
            stringsToHash.append(versionsHash)
        }
        return try contentHasher.hash(stringsToHash)
    }
}
