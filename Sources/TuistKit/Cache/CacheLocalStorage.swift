import Basic
import Foundation
import RxSwift
import TuistSupport

enum CacheLocalStorageError: FatalError {
    case fileNotFound(hash: String)

    var type: ErrorType {
        switch self {
        case .fileNotFound: return .abort
        }
    }

    var description: String {
        switch self {
        case let .fileNotFound(hash):
            return "File with hash \(hash) not found in the local cache"
        }
    }
}

final class CacheLocalStorage: CacheStoraging {
    // MARK: - Attributes

    private let cacheDirectory: AbsolutePath

    // MARK: - Init

    init(cacheDirectory: AbsolutePath = Environment.shared.xcframeworksCacheDirectory) {
        self.cacheDirectory = cacheDirectory
    }

    // MARK: - CacheStoraging

    func exists(hash: String) -> Single<Bool> {
        Single.create { (completed) -> Disposable in
            completed(.success(FileHandler.shared.glob(self.cacheDirectory, glob: "\(hash)/*").count != 0))
            return Disposables.create()
        }
    }

    func fetch(hash: String) -> Single<AbsolutePath> {
        Single.create { (completed) -> Disposable in
            if let path = FileHandler.shared.glob(self.cacheDirectory, glob: "\(hash)/*").first {
                completed(.success(path))
            } else {
                completed(.error(CacheLocalStorageError.fileNotFound(hash: hash)))
            }
            return Disposables.create()
        }
    }

    func store(hash: String, path: AbsolutePath) -> Completable {
        let copy = Completable.create { (completed) -> Disposable in
            let hashFolder = self.cacheDirectory.appending(component: hash)
            let destinationPath = hashFolder.appending(component: path.basename)

            do {
                if !FileHandler.shared.exists(hashFolder) {
                    try FileHandler.shared.createFolder(hashFolder)
                }

                try FileHandler.shared.copy(from: path, to: destinationPath)

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
