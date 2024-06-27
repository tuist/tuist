import Foundation
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol CloudOrganizationShowServicing {
    func run(
        organizationName: String,
        json: Bool,
        directory: String?
    ) async throws
}

final class CloudOrganizationShowService: CloudOrganizationShowServicing {
    private let getOrganizationService: GetOrganizationServicing
    private let getOrganizationUsageService: GetOrganizationUsageServicing
    private let cloudURLService: CloudURLServicing
    private let configLoader: ConfigLoading

    init(
        getOrganizationService: GetOrganizationServicing = GetOrganizationService(),
        getOrganizationUsageService: GetOrganizationUsageServicing = GetOrganizationUsageService(),
        cloudURLService: CloudURLServicing = CloudURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.getOrganizationService = getOrganizationService
        self.getOrganizationUsageService = getOrganizationUsageService
        self.cloudURLService = cloudURLService
        self.configLoader = configLoader
    }

    func run(
        organizationName: String,
        json: Bool,
        directory: String?
    ) async throws {
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(validating: directory, relativeTo: FileHandler.shared.currentPath)
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
        let config = try configLoader.loadConfig(path: directoryPath)
        let cloudURL = try cloudURLService.url(configCloudURL: config.cloud?.url)

        let organization = try await getOrganizationService.getOrganization(
            organizationName: organizationName,
            serverURL: cloudURL
        )

        let organizationUsage = try await getOrganizationUsageService.getOrganizationUsage(
            organizationName: organizationName,
            serverURL: cloudURL
        )

        if json {
            let json = try organization.toJSON()
            logger.info(.init(stringLiteral: json.toString(prettyPrint: true)), metadata: .json)
            return
        }

        let membersHeaders = ["username", "email", "role"]
        let membersTable = formatDataToTable(
            [membersHeaders] + organization.members.map { [$0.name, $0.email, $0.role.rawValue] }
        )

        let invitationsString: String
        if organization.invitations.isEmpty {
            invitationsString = "There are currently no invited users."
        } else {
            let invitationsHeaders = ["inviter", "invitee email"]
            let invitationsTable = formatDataToTable(
                [invitationsHeaders] + organization.invitations.map { [$0.inviter.name, $0.inviteeEmail] }
            )
            invitationsString = """
            \("Invitations".bold()) (total number: \(organization.invitations.count))
            \(invitationsTable)
            """
        }

        var baseInfo = [
            "Organization".bold(),
            "Name: \(organization.name)",
            "Plan: \(organization.plan.rawValue.capitalized)",
        ]

        if let ssoOrganization = organization.ssoOrganization {
            switch ssoOrganization {
            case let .google(organizationId):
                baseInfo.append("SSO: Google (\(organizationId))")
            }
        }

        logger.info("""
        \(baseInfo.joined(separator: "\n"))

        \("Usage".bold()) (current calendar month)
        Remote cache hits: \(organizationUsage.currentMonthRemoteCacheHits)

        \("Organization members".bold()) (total number: \(organization.members.count))
        \(membersTable)

        \(invitationsString)
        """)
    }

    private func formatDataToTable(_ data: [[String]]) -> String {
        guard !data.isEmpty else {
            return ""
        }

        var tableString = ""

        // Calculate the maximum width of each column
        let columnWidths = data[0].indices.map { colIndex -> Int in
            (
                data.map { $0[colIndex].count }.max() ?? 0
            ) + 2
        }

        // Format the data into the `tableString`
        for (index, row) in data.enumerated() {
            for (index, dataPoint) in row.enumerated() {
                if index != row.endIndex - 1 {
                    tableString += dataPoint.paddedToWidth(columnWidths[index])
                } else {
                    tableString += dataPoint
                }
            }
            if index != data.endIndex - 1 {
                tableString += "\n"
            }
        }

        return tableString
    }
}

extension String {
    fileprivate func paddedToWidth(_ width: Int) -> String {
        let length = count
        guard length < width else {
            return self
        }

        let spaces = [Character](repeating: " ", count: width - length)
        return self + spaces
    }
}
