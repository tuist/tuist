import Foundation
import Mockable
import Path
import TuistSupport

enum AppBundleServiceError: FatalError, Equatable {
    case missingInfoPlist(AbsolutePath)

    var description: String {
        switch self {
        case let .missingInfoPlist(path):
            return "Expected Info.plist at \(path) was not found. Make sure it exists."
        }
    }

    var type: ErrorType {
        switch self {
        case .missingInfoPlist:
            return .abort
        }
    }
}

@Mockable
public protocol AppBundleServicing {
    func read(_ appBundle: AbsolutePath) throws -> AppBundle
}

public struct AppBundleService: AppBundleServicing {
    private let fileHandler: FileHandling

    public init() {
        self.init(
            fileHandler: FileHandler.shared
        )
    }

    init(
        fileHandler: FileHandling
    ) {
        self.fileHandler = fileHandler
    }

    public func read(_ appBundle: AbsolutePath) throws -> AppBundle {
        let infoPlistPath = appBundle.appending(component: "Info.plist")

        if !fileHandler.exists(infoPlistPath) {
            throw AppBundleServiceError.missingInfoPlist(infoPlistPath)
        }

        let data = try Data(contentsOf: infoPlistPath.url)
        let decoder = PropertyListDecoder()
        let infoPlist = try decoder.decode(AppBundle.InfoPlist.self, from: data)

        return AppBundle(
            path: appBundle,
            infoPlist: infoPlist
        )
    }
}
