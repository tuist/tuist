import Foundation
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol AccountTokensListCommandServicing {
    func run(
        accountHandle: String,
        directory: String?
    ) async throws
}

final class AccountTokensListCommandService: AccountTokensListCommandServicing {
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
        directory: String?
    ) async throws {
        let path = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        let config = try await configLoader.loadConfig(path: path)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let tokens = try await listAccountTokensService.listAccountTokens(
            accountHandle: accountHandle,
            serverURL: serverURL
        )

        if tokens.isEmpty {
            Logger.current
                .notice(
                    "No account tokens found. Create one by running `tuist account tokens create \(accountHandle) --scopes <scopes> --name <name>`."
                )
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short

            let textTable = TextTable<Operations.listAccountTokens.Output.Ok.Body.jsonPayload.tokensPayloadPayload> {
                [
                    TextTable.Column(title: "ID", value: $0.id),
                    TextTable.Column(title: "Name", value: $0.name ?? "-"),
                    TextTable.Column(title: "Scopes", value: $0.scopes.map(\.rawValue).joined(separator: ", ")),
                    TextTable.Column(title: "Projects", value: $0.all_projects ? "All" : ($0.project_handles ?? []).joined(separator: ", ")),
                    TextTable.Column(title: "Expires", value: $0.expires_at.map { dateFormatter.string(from: $0) } ?? "Never"),
                    TextTable.Column(title: "Created", value: dateFormatter.string(from: $0.inserted_at)),
                ]
            }
            Logger.current.notice("\(textTable.render(tokens))")
        }
    }
}
