@preconcurrency import FileSystem
import Foundation
import Mockable
import Path

enum AppBundleLoaderError: LocalizedError, Equatable {
    case missingInfoPlist(AbsolutePath)
    case failedDecodingInfoPlist(AbsolutePath, String)

    var errorDescription: String? {
        switch self {
        case let .missingInfoPlist(path):
            return "Expected Info.plist at \(path) was not found. Make sure it exists."
        case let .failedDecodingInfoPlist(path, reason):
            return "Failed decoding Info.plist at \(path) due to: \(reason)"
        }
    }
}

@Mockable
protocol AppBundleLoading: Sendable {
    func load(_ appBundle: AbsolutePath) async throws -> AppBundle
}

struct AppBundleLoader: AppBundleLoading {
    private let fileSystem: FileSysteming

    init(
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.fileSystem = fileSystem
    }

    func load(_ appBundle: AbsolutePath) async throws -> AppBundle {
        // macOS bundles use Contents/ subdirectory layout, other Apple platforms use flat layout.
        let isMacOSBundle = try await fileSystem.exists(appBundle.appending(component: "Contents"), isDirectory: true)
        let infoPlistPath = isMacOSBundle
            ? appBundle.appending(components: "Contents", "Info.plist")
            : appBundle.appending(component: "Info.plist")

        guard try await fileSystem.exists(infoPlistPath) else {
            throw AppBundleLoaderError.missingInfoPlist(infoPlistPath)
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: infoPlistPath.pathString))
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
