import Foundation
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport

enum CacheLocalStorageError: FatalError, Equatable {
    case xcframeworkNotFound(hash: String)

    var type: ErrorType {
        switch self {
        case .xcframeworkNotFound: return .abort
        }
    }

    var description: String {
        switch self {
        case let .xcframeworkNotFound(hash):
            return "xcframework with hash '\(hash)' not found in the local cache"
        }
    }
}

public final class CacheLocalStorage: CacheStoring {
    // MARK: - Attributes

    private let cacheDirectory: AbsolutePath

    // MARK: - Init

    public convenience init(cacheDirectoriesProvider: CacheDirectoriesProviding) {
        self.init(cacheDirectory: cacheDirectoriesProvider.buildCacheDirectory)
    }

    init(cacheDirectory: AbsolutePath) {
        self.cacheDirectory = cacheDirectory
    }

    // MARK: - CacheStoring

    public func exists(hash: String) -> Single<Bool> {
        Single.create { (completed) -> Disposable in
            completed(.success(self.lookupFramework(directory: self.cacheDirectory.appending(component: hash)) != nil))
            return Disposables.create()
        }
    }

    public func fetch(hash: String) -> Single<AbsolutePath> {
        Single.create { (completed) -> Disposable in
            if let path = self.lookupFramework(directory: self.cacheDirectory.appending(component: hash)) {
                completed(.success(path))
            } else {
                completed(.error(CacheLocalStorageError.xcframeworkNotFound(hash: hash)))
            }
            return Disposables.create()
        }
    }

    public func store(hash: String, paths: [AbsolutePath]) -> Completable {
        let copy = Completable.create { (completed) -> Disposable in
            let hashFolder = self.cacheDirectory.appending(component: hash)

            do {
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
            } catch {
                completed(.error(error))
                return Disposables.create()
            }
            completed(.completed)
            return Disposables.create()
        }

        return createCacheDirectory().concat(copy)
    }

    // MARK: - Fileprivate

    fileprivate func lookupFramework(directory: AbsolutePath) -> AbsolutePath? {
        let extensions = ["framework", "xcframework"]
        for ext in extensions {
            if let filePath = FileHandler.shared.glob(directory, glob: "*.\(ext)").first { return filePath }
        }
        return nil
    }

    fileprivate func createCacheDirectory() -> Completable {
        Completable.create { (completed) -> Disposable in
            do {
                if !FileHandler.shared.exists(self.cacheDirectory) {
                    try FileHandler.shared.createFolder(self.cacheDirectory)
                }
            } catch {
                completed(.error(error))
                return Disposables.create()
            }
            completed(.completed)
            return Disposables.create()
        }
    }
}
