import Foundation
import Path
import TSCBasic
import TuistConfigLoader
import TuistEncodable
import TuistEnvironment
import TuistLogging
import TuistServer

protocol OrganizationShowServicing {
    func run(
        organizationName: String,
        json: Bool,
        directory: String?
    ) async throws
}

struct OrganizationShowService: OrganizationShowServicing {
    private let getOrganizationService: GetOrganizationServicing
    private let getOrganizationUsageService: GetOrganizationUsageServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        getOrganizationService: GetOrganizationServicing = GetOrganizationService(),
        getOrganizationUsageService: GetOrganizationUsageServicing = GetOrganizationUsageService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.getOrganizationService = getOrganizationService
        self.getOrganizationUsageService = getOrganizationUsageService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        organizationName: String,
        json: Bool,
        directory: String?
    ) async throws {
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let organization = try await getOrganizationService.getOrganization(
            organizationName: organizationName,
            serverURL: serverURL
        )

        let organizationUsage = try await getOrganizationUsageService.getOrganizationUsage(
            organizationName: organizationName,
            serverURL: serverURL
        )

        if json {
            let json = try jsonOutput(organization: organization, usage: organizationUsage)
            Logger.current.info(
                .init(stringLiteral: json.toString(prettyPrint: true)), metadata: .json
            )
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
                [invitationsHeaders]
                    + organization.invitations.map { [$0.inviter.name, $0.inviteeEmail] }
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
            case let .okta(organizationId):
                baseInfo.append("SSO: Okta (\(organizationId))")
            }
        }

        Logger.current.info(
            """
            \(baseInfo.joined(separator: "\n"))

            \(usageSection(organizationUsage))

            \("Organization members".bold()) (total number: \(organization.members.count))
            \(membersTable)

            \(invitationsString)
            """
        )
    }

    private func jsonOutput(organization: ServerOrganization, usage: ServerOrganizationUsage) throws -> JSON {
        let organizationJSON = try organization.toJSON()
        guard case var .dictionary(fields) = organizationJSON else { return organizationJSON }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        fields["usage"] = try JSON(data: encoder.encode(usage))
        return .dictionary(fields)
    }

    private func usageSection(_ usage: ServerOrganizationUsage) -> String {
        let period = formatPeriod(start: usage.periodStart, end: usage.periodEnd)
        let cacheEgress = "\(formatGigabytes(usage.cacheEgress.used)) of \(formatGigabytes(usage.cacheEgress.included))"
        let cacheRequests = "\(formatCount(usage.cacheRequests.used)) of \(formatCount(usage.cacheRequests.included))"
        let passingTestCases =
            "\(formatCount(usage.passingTestCases.used)) of \(formatCount(usage.passingTestCases.included))"
        let runnerMinutes = "\(formatCount(usage.runnerMinutes.used)) of \(formatCount(usage.runnerMinutes.included))"

        return """
        \("Usage".bold()) (\(period))
        Cache egress: \(cacheEgress) included
        Cache requests: \(cacheRequests) included
        Passing test cases: \(passingTestCases) included
        Runner minutes: \(runnerMinutes) included
        Estimated charge: \(formatDollars(cents: usage.estimatedChargeCents))
        """
    }

    private func formatPeriod(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "MMM d"
        let startString = formatter.string(from: start)
        formatter.dateFormat = "MMM d, yyyy"
        return "\(startString) to \(formatter.string(from: end))"
    }

    private func formatGigabytes(_ bytes: Int) -> String {
        let formatter = numberFormatter()
        formatter.maximumFractionDigits = 1
        return "\(formatter.string(from: NSNumber(value: Double(bytes) / 1_000_000_000)) ?? "0") GB"
    }

    private func formatCount(_ count: Int) -> String {
        numberFormatter().string(from: NSNumber(value: count)) ?? String(count)
    }

    private func formatDollars(cents: Int) -> String {
        let formatter = numberFormatter()
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "$\(formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "0.00")"
    }

    private func numberFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        return formatter
    }

    private func formatDataToTable(_ data: [[String]]) -> String {
        guard !data.isEmpty else {
            return ""
        }

        var tableString = ""

        // Calculate the maximum width of each column
        let columnWidths = data[0].indices.map { colIndex -> Int in
            (data.map { $0[colIndex].count }.max() ?? 0) + 2
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
