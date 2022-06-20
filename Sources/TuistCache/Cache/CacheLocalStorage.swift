import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public final class CacheLocalStorage: CacheStoring {
    // MARK: - Attributes

    private let cacheDirectory: AbsolutePath

    // MARK: - Init

    public convenience init(cacheDirectoriesProvider: CacheDirectoriesProviding) {
        self.init(cacheDirectory: cacheDirectoriesProvider.cacheDirectory(for: .builds))
    }

    init(cacheDirectory: AbsolutePath) {
        self.cacheDirectory = cacheDirectory
    }

    // MARK: - CacheStoring

    public func exists(name: String, hash: String) -> Bool {
        let hashFolder = cacheDirectory.appending(component: hash)
        let exists = lookupCompiledArtifact(directory: hashFolder) != nil
        if exists {
            CacheAnalytics.localCacheTargetsHits.insert(name)
        }
        return exists
    }

    public func fetch(name _: String, hash: String) -> AbsolutePath? {
        let hashFolder = cacheDirectory.appending(component: hash)
        return lookupCompiledArtifact(directory: hashFolder)
    }

    public func store(name _: String, hash: String, paths: [AbsolutePath]) throws {
        if !FileHandler.shared.exists(cacheDirectory) {
            try FileHandler.shared.createFolder(cacheDirectory)
        }

        let hashFolder = cacheDirectory.appending(component: hash)

        if !FileHandler.shared.exists(hashFolder) {
            try FileHandler.shared.createFolder(hashFolder)
        }
        try paths.forEach { sourcePath in
            let destinationPath = hashFolder.appending(component: sourcePath.basename)
            if FileHandler.shared.exists(destinationPath) {
                try FileHandler.shared.delete(destinationPath)
            }
            try FileHandler.shared.copy(from: sourcePath, to: destinationPath)
        }
    }

    // MARK: - Fileprivate

    fileprivate func lookupCompiledArtifact(directory: AbsolutePath) -> AbsolutePath? {
        let extensions = ["framework", "xcframework", "bundle"]
        for ext in extensions {
            if let filePath = FileHandler.shared.glob(directory, glob: "*.\(ext)").first { return filePath }
        }
        return nil
    }
}
