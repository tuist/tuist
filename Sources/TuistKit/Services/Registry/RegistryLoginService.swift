import FileSystem
import Foundation
import Path
import TuistLoader
import TuistServer
import TuistSupport

enum RegistryLoginServiceError: Equatable, FatalError {
    case missingFullHandle
    case missingProjectToken

    var type: TuistSupport.ErrorType {
        switch self {
        case .missingFullHandle, .missingProjectToken: .abort
        }
    }

    var description: String {
        switch self {
        case .missingFullHandle:
            return "Login to the registry failed because the project is missing the 'fullHandle' in the 'Tuist.swift' file."
        case .missingProjectToken:
            return "The project token is needed to interact with the registry on the CI. Make sure the 'TUIST_CONFIG_TOKEN' environment variable is present and valid."
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

    init(
        createAccountTokenService: CreateAccountTokenServicing = CreateAccountTokenService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader(warningController: WarningController.shared),
        fileSystem: FileSysteming = FileSystem(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        ciChecker: CIChecking = CIChecker(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController()
    ) {
        self.createAccountTokenService = createAccountTokenService
        self.serverURLService = serverURLService
        self.configLoader = configLoader
        self.fileSystem = fileSystem
        self.fullHandleService = fullHandleService
        self.swiftPackageManagerController = swiftPackageManagerController
        self.ciChecker = ciChecker
        self.serverAuthenticationController = serverAuthenticationController
    }

    func run(
        path: String?
    ) async throws {
        let path = try await self.path(path)
        let config = try await configLoader.loadConfig(path: path)

        guard let fullHandle = config.fullHandle else { throw RegistryLoginServiceError.missingFullHandle }
        let accountHandle = try fullHandleService.parse(fullHandle).accountHandle

        logger.info("Logging into the registry...")
        let serverURL = try serverURLService.url(configServerURL: config.url)

        let token: String
        if ciChecker.isCI() {
            switch try await serverAuthenticationController.authenticationToken(serverURL: serverURL) {
            case let .project(projectToken):
                token = projectToken
            case .user, .none:
                throw RegistryLoginServiceError.missingProjectToken
            }
        } else {
            token = try await createAccountTokenService.createAccountToken(
                accountHandle: accountHandle,
                scopes: [.accountRegistryRead],
                serverURL: serverURL
            )
        }

        let registryURL = serverURL.appending(path: "api/accounts/\(accountHandle)/registry/swift")

        try await swiftPackageManagerController.packageRegistryLogin(
            token: token,
            registryURL: registryURL
        )

        logger.info("Successfully logged in to the \(accountHandle) registry 🎉")
    }

    private func path(_ path: String?) async throws -> AbsolutePath {
        if let path {
            return try await AbsolutePath(validating: path, relativeTo: fileSystem.currentWorkingDirectory())
        } else {
            return try await fileSystem.currentWorkingDirectory()
        }
    }
}
