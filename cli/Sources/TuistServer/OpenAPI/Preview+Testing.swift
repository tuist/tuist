#if MOCKING
    import Foundation

    extension Components.Schemas.Preview {
        public static func test(
            builds: [Components.Schemas.AppBuild] = [.test()],
            bundleIdentifier: String? = "dev.tuist.app",
            createdFromCI: Bool = false,
            deviceURL: URL = URL(string: "https://tuist.dev/tuist/tuist/previews/preview-id/device")!,
            displayName: String? = "App",
            gitBranch: String? = nil,
            gitCommitSHA: String? = nil,
            iconURL: URL = URL(string: "https://tuist.dev/tuist/tuist/previews/preview-id/icon")!,
            id: String = "preview-id",
            insertedAt: String = "2024-01-01T00:00:00Z",
            qrCodeURL: URL = URL(string: "https://tuist.dev/tuist/tuist/previews/preview-id/qr-code.svg")!,
            supportedPlatforms: [Components.Schemas.PreviewSupportedPlatform] = [.ios, .ios_simulator],
            track: String? = nil,
            url: URL = URL(string: "https://tuist.dev/tuist/tuist/previews/preview-id")!,
            version: String? = nil
        ) -> Self {
            .init(
                builds: builds,
                bundle_identifier: bundleIdentifier,
                created_from_ci: createdFromCI,
                device_url: deviceURL.absoluteString,
                display_name: displayName,
                git_branch: gitBranch,
                git_commit_sha: gitCommitSHA,
                icon_url: iconURL.absoluteString,
                id: id,
                inserted_at: insertedAt,
                qr_code_url: qrCodeURL.absoluteString,
                supported_platforms: supportedPlatforms,
                track: track,
                url: url.absoluteString,
                version: version
            )
        }
    }

    extension Components.Schemas.AppBuild {
        public static func test(
            binaryId: String? = nil,
            id: String = "app-build-id",
            supportedPlatforms: [Components.Schemas.PreviewSupportedPlatform] = [.ios, .ios_simulator],
            type: Components.Schemas.AppBuild._typePayload = .app_bundle,
            url: URL = URL(string: "https://tuist.dev/tuist/tuist/previews/app-build-id")!
        ) -> Self {
            .init(
                binary_id: binaryId,
                id: id,
                supported_platforms: supportedPlatforms,
                _type: type,
                url: url.absoluteString
            )
        }
    }
#endif
