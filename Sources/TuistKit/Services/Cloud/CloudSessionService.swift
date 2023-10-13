#if canImport(TuistCloud)
    import Foundation
    import TSCBasic
    import TuistCloud
    import TuistCore
    import TuistLoader
    import TuistSupport

    protocol CloudSessionServicing: AnyObject {
        /// It prints any existing session in the keychain to authenticate
        /// on a server identified by that URL.
        func printSession(
            directory: String?
        ) throws
    }

    final class CloudSessionService: CloudSessionServicing {
        private let cloudSessionController: CloudSessionControlling
        private let cloudURLService: CloudURLServicing
        private let configLoader: ConfigLoading

        // MARK: - Init

        init(
            cloudSessionController: CloudSessionControlling = CloudSessionController(),
            cloudURLService: CloudURLServicing = CloudURLService(),
            configLoader: ConfigLoading = ConfigLoader()
        ) {
            self.cloudSessionController = cloudSessionController
            self.cloudURLService = cloudURLService
            self.configLoader = configLoader
        }

        // MARK: - CloudAuthServicing

        func printSession(
            directory: String?
        ) throws {
            let directoryPath: AbsolutePath
            if let directory {
                directoryPath = try AbsolutePath(validating: directory, relativeTo: FileHandler.shared.currentPath)
            } else {
                directoryPath = FileHandler.shared.currentPath
            }
            let config = try configLoader.loadConfig(path: directoryPath)
            let cloudURL = try cloudURLService.url(configCloudURL: config.cloud?.url)
            try cloudSessionController.printSession(serverURL: cloudURL)
        }
    }
#endif
