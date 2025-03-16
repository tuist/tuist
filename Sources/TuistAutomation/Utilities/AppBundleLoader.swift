import FileSystem
import Foundation
import Mockable
import Path
import TuistSupport

enum AppBundleLoaderError: FatalError, Equatable {
    case missingInfoPlist(AbsolutePath)
    case failedDecodingInfoPlist(AbsolutePath, String)

    var description: String {
        switch self {
        case let .missingInfoPlist(path):
            return "Expected Info.plist at \(path) was not found. Make sure it exists."
        case let .failedDecodingInfoPlist(path, reason):
            return "Failed decoding Info.plist at \(path) due to: \(reason)"
        }
    }

    var type: ErrorType {
        switch self {
        case .missingInfoPlist, .failedDecodingInfoPlist:
            return .abort
        }
    }
}

@Mockable
public protocol AppBundleLoading {
    func load(_ appBundle: AbsolutePath) async throws -> AppBundle
}

public struct AppBundleLoader: AppBundleLoading {
    private let fileSystem: FileSysteming

    public init() {
        self.init(
            fileSystem: FileSystem()
        )
    }

    init(
        fileSystem: FileSysteming
    ) {
        self.fileSystem = fileSystem
    }

    public func load(_ appBundle: AbsolutePath) async throws -> AppBundle {
        let infoPlistPath = appBundle.appending(component: "Info.plist")

        if try await !fileSystem.exists(infoPlistPath) {
            throw AppBundleLoaderError.missingInfoPlist(infoPlistPath)
        }

        let data = try Data(contentsOf: infoPlistPath.url)
        let decoder = PropertyListDecoder()

        let infoPlist: AppBundle.InfoPlist
        do {
            infoPlist = try decoder.decode(AppBundle.InfoPlist.self, from: data)
        } catch {
            throw AppBundleLoaderError.failedDecodingInfoPlist(infoPlistPath, error.localizedDescription)
        }

        return AppBundle(
            path: appBundle,
            infoPlist: infoPlist
        )
    }
}
