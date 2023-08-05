import Foundation
import TSCBasic
import TuistCloud
import TuistLoader
import TuistSupport

protocol CloudOrganizationShowServicing {
    func run(
        organizationName: String,
        json: Bool,
        serverURL: String?
    ) async throws
}

final class CloudOrganizationShowService: CloudOrganizationShowServicing {
    private let getOrganizationService: GetOrganizationServicing
    private let cloudURLService: CloudURLServicing

    init(
        getOrganizationService: GetOrganizationServicing = GetOrganizationService(),
        cloudURLService: CloudURLServicing = CloudURLService()
    ) {
        self.getOrganizationService = getOrganizationService
        self.cloudURLService = cloudURLService
    }

    func run(
        organizationName: String,
        json: Bool,
        serverURL: String?
    ) async throws {
        let cloudURL = try cloudURLService.url(serverURL: serverURL)

        let organization = try await getOrganizationService.getOrganization(
            organizationName: organizationName,
            serverURL: cloudURL
        )

        if json {
            let json = try organization.toJSON()
            logger.info(.init(stringLiteral: json.toString(prettyPrint: true)))
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

        logger.info("""
        \("Organization".bold())
        Name: \(organization.name)

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
