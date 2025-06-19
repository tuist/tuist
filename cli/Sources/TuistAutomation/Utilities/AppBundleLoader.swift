import FileSystem
import Foundation
import Mockable
import Path
import TuistSupport

enum AppBundleLoaderError: LocalizedError, Equatable {
    case missingInfoPlist(AbsolutePath)
    case failedDecodingInfoPlist(AbsolutePath, String)
    case appBundleInIPANotFound(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case let .missingInfoPlist(path):
            return "Expected Info.plist at \(path) was not found. Make sure it exists."
        case let .failedDecodingInfoPlist(path, reason):
            return "Failed decoding Info.plist at \(path) due to: \(reason)"
        case let .appBundleInIPANotFound(ipaPath):
            return
                "No app found in the .ipa archive at \(ipaPath). Make sure the .ipa is a valid application archive."
        }
    }
}

@Mockable
public protocol AppBundleLoading {
    func load(_ appBundle: AbsolutePath) async throws -> AppBundle
    func load(ipa: AbsolutePath) async throws -> AppBundle
}

public struct AppBundleLoader: AppBundleLoading {
    private let fileSystem: FileSysteming
    private let fileArchiverFactory: FileArchivingFactorying

    public init() {
        self.init(
            fileSystem: FileSystem()
        )
    }

    init(
        fileSystem: FileSysteming,
        fileArchiverFactory: FileArchivingFactorying = FileArchivingFactory()
    ) {
        self.fileSystem = fileSystem
        self.fileArchiverFactory = fileArchiverFactory
    }

    public func load(ipa: AbsolutePath) async throws -> AppBundle {
        let unarchivedIPA = try fileArchiverFactory.makeFileUnarchiver(for: ipa).unzip()

        guard let appBundlePath = try await fileSystem.glob(
            directory: unarchivedIPA,
            include: ["**/*.app"]
        )
        .collect()
        .first
        else { throw AppBundleLoaderError.appBundleInIPANotFound(ipa) }

        let appBundleInfoPlist = try await load(appBundlePath).infoPlist
        return AppBundle(
            path: ipa,
            infoPlist: appBundleInfoPlist
        )
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
