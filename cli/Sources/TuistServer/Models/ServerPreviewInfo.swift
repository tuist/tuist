import Foundation

public struct ServerPreviewBuild: Sendable, Equatable {
    public let id: String
    public let url: URL
    public let supportedPlatforms: [Components.Schemas.PreviewSupportedPlatform]
    public let type: Components.Schemas.AppBuild._typePayload

    public init(
        id: String,
        url: URL,
        supportedPlatforms: [Components.Schemas.PreviewSupportedPlatform],
        type: Components.Schemas.AppBuild._typePayload
    ) {
        self.id = id
        self.url = url
        self.supportedPlatforms = supportedPlatforms
        self.type = type
    }
}

public struct ServerPreviewInfo: Sendable, Equatable {
    public let id: String
    public let url: URL
    public let bundleIdentifier: String?
    public let displayName: String?
    public let builds: [ServerPreviewBuild]
    public let supportedPlatforms: [Components.Schemas.PreviewSupportedPlatform]

    public init(
        id: String,
        url: URL,
        bundleIdentifier: String?,
        displayName: String?,
        builds: [ServerPreviewBuild],
        supportedPlatforms: [Components.Schemas.PreviewSupportedPlatform]
    ) {
        self.id = id
        self.url = url
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.builds = builds
        self.supportedPlatforms = supportedPlatforms
    }
}

extension ServerPreviewInfo {
    init?(_ preview: Components.Schemas.Preview) {
        guard let url = URL(string: preview.url)
        else { return nil }
        self.id = preview.id
        self.url = url
        self.bundleIdentifier = preview.bundle_identifier
        self.displayName = preview.display_name
        self.builds = preview.builds.compactMap { build in
            guard let url = URL(string: build.url) else { return nil }
            return ServerPreviewBuild(
                id: build.id,
                url: url,
                supportedPlatforms: build.supported_platforms,
                type: build._type
            )
        }
        self.supportedPlatforms = preview.supported_platforms
    }
}

#if DEBUG
    extension ServerPreviewInfo {
        public static func test(
            id: String = "preview-id",
            url: URL = URL(string: "https://tuist.dev/tuist/tuist/previews/preview-id")!,
            bundleIdentifier: String? = "dev.tuist.app",
            displayName: String? = "App",
            builds: [ServerPreviewBuild] = [
                .test(),
            ],
            supportedPlatforms: [Components.Schemas.PreviewSupportedPlatform] = [
                .ios,
                .ios_simulator,
            ]
        ) -> Self {
            .init(
                id: id,
                url: url,
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                builds: builds,
                supportedPlatforms: supportedPlatforms
            )
        }
    }

    extension ServerPreviewBuild {
        public static func test(
            id: String = "app-build-id",
            url: URL = URL(string: "https://tuist.dev/tuist/tuist/previews/app-build-id")!,
            supportedPlatforms: [Components.Schemas.PreviewSupportedPlatform] = [.ios, .ios_simulator],
            type: Components.Schemas.AppBuild._typePayload = .app_bundle
        ) -> ServerPreviewBuild {
            self.init(
                id: id,
                url: url,
                supportedPlatforms: supportedPlatforms,
                type: type
            )
        }
    }
#endif
