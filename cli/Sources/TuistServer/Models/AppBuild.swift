import Foundation
import TuistSimulator
import XcodeGraph

public struct AppBuild: Hashable, Sendable, Equatable, Codable {
    public let id: String
    public let url: URL
    public let supportedPlatforms: [DestinationType]
    public let type: AppBuildType
}

extension AppBuild {
    init?(_ appBuild: Components.Schemas.AppBuild) {
        id = appBuild.id
        guard let url = URL(string: appBuild.url)
        else { return nil }
        self.url = url
        supportedPlatforms = appBuild.supported_platforms.map(DestinationType.init)
        type = AppBuildType(appBuild._type)
    }
}

#if DEBUG
    extension AppBuild {
        public static func test(
            id: String = "app-build-id",
            url: URL = URL(string: "https://tuist.dev/tuist/tuist/previews/app-build-id")!,
            supportedPlatforms: [DestinationType] = [.device(.iOS), .simulator(.iOS)],
            type: AppBuildType = .appBundle
        ) -> AppBuild {
            self.init(
                id: id,
                url: url,
                supportedPlatforms: supportedPlatforms,
                type: type
            )
        }
    }
#endif

public enum AppBuildType: Sendable, Equatable, Codable {
    case appBundle, ipa
}

extension AppBuildType {
    init(_ appBuildType: Components.Schemas.AppBuild._typePayload) {
        switch appBuildType {
        case .app_bundle:
            self = .appBundle
        case .ipa:
            self = .ipa
        }
    }
}
