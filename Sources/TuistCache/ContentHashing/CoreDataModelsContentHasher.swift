import Foundation
import TuistCore

public protocol CoreDataModelsContentHashing {
    func hash(coreDataModels: [CoreDataModel]) throws -> String
}

public final class CoreDataModelsContentHasher: CoreDataModelsContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing = ContentHasher()) {
        self.contentHasher = contentHasher
    }

    // MARK: - CoreDataModelsContentHashing
    
    public func hash(coreDataModels: [CoreDataModel]) throws -> String {
        var stringsToHash: [String] = []
        for cdModel in coreDataModels {
            let contentHash = try contentHasher.hash(cdModel.path)
            let currentVersionHash = try contentHasher.hash([cdModel.currentVersion])
            let cdModelHash = try contentHasher.hash([contentHash, currentVersionHash])
            let versionsHash = try contentHasher.hash(cdModel.versions.map { $0.pathString })
            stringsToHash.append(cdModelHash)
            stringsToHash.append(versionsHash)
        }
        return try contentHasher.hash(stringsToHash)
    }
}
