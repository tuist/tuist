#if canImport(TuistCloud)
    import Foundation
    import TSCBasic
    import TuistCloud
    import TuistLoader
    import TuistSupport

    protocol CloudOrganizationInviteServicing {
        func run(
            organizationName: String,
            email: String,
            directory: String?
        ) async throws
    }

    final class CloudOrganizationInviteService: CloudOrganizationInviteServicing {
        private let createOrganizationInviteService: CreateOrganizationInviteServicing
        private let cloudURLService: CloudURLServicing
        private let configLoader: ConfigLoading
        
        init(
            createOrganizationInviteService: CreateOrganizationInviteServicing = CreateOrganizationInviteService(),
            cloudURLService: CloudURLServicing = CloudURLService(),
            configLoader: ConfigLoading = ConfigLoader()
        ) {
            self.createOrganizationInviteService = createOrganizationInviteService
            self.cloudURLService = cloudURLService
            self.configLoader = configLoader
        }

        func run(
            organizationName: String,
            email: String,
            directory: String?
        ) async throws {
            let directoryPath: AbsolutePath
            if let directory {
                directoryPath = try AbsolutePath(validating: directory, relativeTo: FileHandler.shared.currentPath)
            } else {
                directoryPath = FileHandler.shared.currentPath
            }
            let config = try self.configLoader.loadConfig(path: directoryPath)
            let cloudURL = try cloudURLService.url(configCloudURL: config.cloud?.url)


            let invitation = try await createOrganizationInviteService.createOrganizationInvite(
                organizationName: organizationName,
                email: email,
                serverURL: cloudURL
            )

            let invitationURL = cloudURL
                .appendingPathComponent("auth")
                .appendingPathComponent("invitations")
                .appendingPathComponent(invitation.token)

            logger.info("""
            \(invitation.inviteeEmail) was successfully invited to the \(organizationName) organization 🎉

            You can also share with them the invite link directly: \(invitationURL.absoluteString)
            """)
        }
    }
#endif
