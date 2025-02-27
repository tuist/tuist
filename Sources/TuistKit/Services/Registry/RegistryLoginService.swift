import FileSystem
import Foundation
import Path
import ServiceContextModule
import TuistLoader
import TuistServer
import TuistSupport

enum RegistryLoginServiceError: Equatable, FatalError {
    case missingFullHandle
    case missingProjectToken
    case missingHost(URL)

    var type: TuistSupport.ErrorType {
        switch self {
        case .missingFullHandle, .missingProjectToken, .missingHost: .abort
        }
    }

    var description: String {
        switch self {
        case .missingFullHandle:
            return "Login to the registry failed because the project is missing the 'fullHandle' in the 'Tuist.swift' file."
        case .missingProjectToken:
            return "The project token is needed to interact with the registry on the CI. Make sure the 'TUIST_CONFIG_TOKEN' environment variable is present and valid."
        case let .missingHost(url):
            return "Failed getting host from the Tuist server URL \(url.absoluteString)."
        }
    }
}

struct RegistryLoginService {
    private let createAccountTokenService: CreateAccountTokenServicing
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading
    private let fileSystem: FileSysteming
    private let fullHandleService: FullHandleServicing
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let ciChecker: CIChecking
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let securityController: SecurityControlling
    private let manifestFilesLocator: ManifestFilesLocating
    private let xcodeController: XcodeControlling

    init(
        createAccountTokenService: CreateAccountTokenServicing = CreateAccountTokenService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader(),
        fileSystem: FileSysteming = FileSystem(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        ciChecker: CIChecking = CIChecker(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        securityController: SecurityControlling = SecurityController(),
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator(),
        xcodeController: XcodeControlling = XcodeController()
    ) {
        self.createAccountTokenService = createAccountTokenService
        self.serverURLService = serverURLService
        self.configLoader = configLoader
        self.fileSystem = fileSystem
        self.fullHandleService = fullHandleService
        self.swiftPackageManagerController = swiftPackageManagerController
        self.ciChecker = ciChecker
        self.serverAuthenticationController = serverAuthenticationController
        self.securityController = securityController
        self.manifestFilesLocator = manifestFilesLocator
        self.xcodeController = xcodeController
    }

    func run(
        path: String?
    ) async throws {
        let path = try await self.path(path)
        let config = try await configLoader.loadConfig(path: path)

        guard let fullHandle = config.fullHandle else { throw RegistryLoginServiceError.missingFullHandle }
        let accountHandle = try fullHandleService.parse(fullHandle).accountHandle

        ServiceContext.current?.logger?.info("Logging into the registry...")
        let serverURL = try serverURLService.url(configServerURL: config.url)
        let registryURL = serverURL.appending(path: "api/accounts/\(accountHandle)/registry/swift")

        if ciChecker.isCI() {
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

        ServiceContext.current?.logger?.info("Successfully logged in to the \(accountHandle) registry 🎉")
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
                guard let host = serverURL.host else { throw RegistryLoginServiceError.missingHost(serverURL) }
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
                        xcode.path.appending(components: "Contents", "Developer", "usr", "bin", "xcodebuild").pathString,
                    ]
                )
            } else {
                try await swiftPackageManagerController.packageRegistryLogin(
                    token: projectToken,
                    registryURL: registryURL
                )
            }
        case .user, .none:
            throw RegistryLoginServiceError.missingProjectToken
        }
    }

    private func registryUserLogin(
        accountHandle: String,
        registryURL: URL,
        serverURL: URL
    ) async throws {
        let token = try await createAccountTokenService.createAccountToken(
            accountHandle: accountHandle,
            scopes: [.accountRegistryRead],
            serverURL: serverURL
        )
        try await swiftPackageManagerController.packageRegistryLogin(
            token: token,
            registryURL: registryURL
        )
    }

    private func path(_ path: String?) async throws -> AbsolutePath {
        if let path {
            return try await AbsolutePath(validating: path, relativeTo: fileSystem.currentWorkingDirectory())
        } else {
            return try await fileSystem.currentWorkingDirectory()
        }
    }
}
