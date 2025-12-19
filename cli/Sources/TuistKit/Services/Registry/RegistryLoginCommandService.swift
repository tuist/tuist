import FileSystem
import Foundation
import Noora
import Path
import TuistHTTP
import TuistLoader
import TuistServer
import TuistSupport

enum RegistryLoginCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle
    case missingProjectToken
    case missingHost(URL)

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return
                "Login to the registry failed because the project is missing the 'fullHandle' in the 'Tuist.swift' file."
        case .missingProjectToken:
            return
                "The project token is needed to interact with the registry on the CI. Make sure the 'TUIST_TOKEN' environment variable is present and valid."
        case let .missingHost(url):
            return "Failed getting host from the Tuist server URL \(url.absoluteString)."
        }
    }
}

struct RegistryLoginCommandService {
    private let createAccountTokenService: CreateAccountTokenServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading
    private let fileSystem: FileSysteming
    private let fullHandleService: FullHandleServicing
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let securityController: SecurityControlling
    private let manifestFilesLocator: ManifestFilesLocating
    private let xcodeController: XcodeControlling
    private let defaultsController: DefaultsControlling

    init(
        createAccountTokenService: CreateAccountTokenServicing = CreateAccountTokenService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader(),
        fileSystem: FileSysteming = FileSystem(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        swiftPackageManagerController: SwiftPackageManagerControlling =
            SwiftPackageManagerController(),
        serverAuthenticationController: ServerAuthenticationControlling =
            ServerAuthenticationController(),
        securityController: SecurityControlling = SecurityController(),
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator(),
        xcodeController: XcodeControlling = XcodeController(),
        defaultsController: DefaultsControlling = DefaultsController()
    ) {
        self.createAccountTokenService = createAccountTokenService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
        self.fileSystem = fileSystem
        self.fullHandleService = fullHandleService
        self.swiftPackageManagerController = swiftPackageManagerController
        self.serverAuthenticationController = serverAuthenticationController
        self.securityController = securityController
        self.manifestFilesLocator = manifestFilesLocator
        self.xcodeController = xcodeController
        self.defaultsController = defaultsController
    }

    func run(
        path: String?
    ) async throws {
        let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: path)

        guard let fullHandle = config.fullHandle else {
            throw RegistryLoginCommandServiceError.missingFullHandle
        }
        let accountHandle = try fullHandleService.parse(fullHandle).accountHandle

        try await Noora.current.progressStep(
            message: "Logging into the registry...",
            successMessage: "Logged in to the \(accountHandle) registry",
            errorMessage: nil,
            showSpinner: true
        ) { _ in
            let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
            let registryURL = serverURL.appending(
                path: "api/registry/swift"
            )

            if Environment.current.isCI {
                try await registryCILogin(
                    registryURL: registryURL,
                    serverURL: serverURL,
                    path: path
                )
            } else {
                try await registryUserLogin(
                    accountHandle: accountHandle,
                    registryURL: registryURL,
                    serverURL: serverURL
                )
            }

            try await defaultsController.setPackageDendencySCMToRegistryTransformation(
                .useRegistryIdentityAndSources
            )
        }
    }

    private func registryCILogin(
        registryURL: URL,
        serverURL: URL,
        path: AbsolutePath
    ) async throws {
        switch try await serverAuthenticationController.authenticationToken(serverURL: serverURL) {
        case let .project(projectToken):
            if try await manifestFilesLocator.locatePackageManifest(at: path) == nil {
                // We add internet password to the keychain only if the packages are resolved by Xcode and not SwiftPM directly.
                // This is because when we run `swift package-registry login`, the `swift` CLI gets automatically access to the
                // new entry in the keychain.
                // However, this is _not_ the case for the `xcodebuild` CLI that's used to resolve the packages via Xcode.
                guard let host = serverURL.host else {
                    throw RegistryLoginCommandServiceError.missingHost(serverURL)
                }
                let xcode = try await xcodeController.selected()
                try await securityController.addInternetPassword(
                    accountName: "token",
                    serverName: host,
                    password: projectToken,
                    securityProtocol: .https,
                    update: true,
                    applications: [
                        "/usr/bin/security",
                        "/usr/bin/codesign",
                        "/usr/bin/xcodebuild",
                        "/usr/bin/swift",
                        xcode.path.appending(
                            components: "Contents", "Developer", "usr", "bin", "xcodebuild"
                        ).pathString,
                    ]
                )
            } else {
                try await swiftPackageManagerController.packageRegistryLogin(
                    token: projectToken,
                    registryURL: registryURL
                )
            }
        case .user, .account, .none:
            throw RegistryLoginCommandServiceError.missingProjectToken
        }
    }

    private func registryUserLogin(
        accountHandle: String,
        registryURL: URL,
        serverURL: URL
    ) async throws {
        let result = try await createAccountTokenService.createAccountToken(
            accountHandle: accountHandle,
            scopes: [.account_colon_registry_colon_read],
            name: "registry-login",
            expiresAt: nil,
            projectHandles: nil,
            serverURL: serverURL
        )
        try await swiftPackageManagerController.packageRegistryLogin(
            token: result.token,
            registryURL: registryURL
        )
    }
}
