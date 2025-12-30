import Foundation
import Noora
import Path
import TuistLoader
import TuistServer
import TuistSupport

struct AccountTokensListCommandService {
    private let listAccountTokensService: ListAccountTokensServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listAccountTokensService: ListAccountTokensServicing = ListAccountTokensService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listAccountTokensService = listAccountTokensService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        accountHandle: String,
        path: String?,
        json: Bool
    ) async throws {
        let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: path)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let tokens = try await listAccountTokensService.listAccountTokens(
            accountHandle: accountHandle,
            serverURL: serverURL
        )

        if json {
            try Noora.current.json(tokens)
            return
        }

        if tokens.isEmpty {
            Noora.current.passthrough(
                "No account tokens found. Create one by running `tuist account tokens create \(accountHandle) --scopes <scopes> --name <name>`."
            )
            return
        }

        try Noora.current.paginatedTable(
            TableData(
                columns: [
                    TableColumn(title: "ID", width: .auto),
                    TableColumn(title: "Name", width: .auto),
                    TableColumn(title: "Scopes", width: .auto),
                    TableColumn(title: "Projects", width: .auto),
                    TableColumn(title: "Expires", width: .auto),
                    TableColumn(title: "Created", width: .auto),
                ],
                rows: tokens.map { token in
                    [
                        "\(token.id)",
                        "\(token.name ?? "-")",
                        "\(token.scopes.map(\.rawValue).joined(separator: ", "))",
                        "\(token.all_projects ? "All" : (token.project_handles ?? []).joined(separator: ", "))",
                        "\(token.expires_at.map { Formatters.formatDate($0) } ?? "Never")",
                        "\(Formatters.formatDate(token.inserted_at))",
                    ]
                }
            ),
            pageSize: 10
        )
    }
}
