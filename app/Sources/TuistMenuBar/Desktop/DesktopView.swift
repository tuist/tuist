import AppKit
import SwiftUI
import TuistAuthentication
import TuistProjects
import TuistServer

public struct DesktopView: View {
    @ObservedObject private var applicationModel: MacApplicationModel
    @ObservedObject private var authenticationService: AuthenticationService

    public init(applicationModel: MacApplicationModel) {
        self.applicationModel = applicationModel
        authenticationService = applicationModel.authenticationService
    }

    public var body: some View {
        Group {
            if case let .loggedIn(account, server) = authenticationService.authenticationState {
                SignedInDesktopView(account: account, applicationModel: applicationModel)
                    .id("\(server?.url.absoluteString ?? "hosted")/\(account.handle)")
                    .toolbar {
                        ToolbarItem(placement: .status) {
                            DesktopActivityView()
                        }
                    }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .macApplicationEnvironment(applicationModel)
        .task {
            guard authenticationService.authenticationState != .loggedOut else { return }
            do {
                try await applicationModel.loadDevices()
            } catch {
                applicationModel.errorHandling.handle(error: error)
            }
        }
    }
}

private struct DesktopActivityView: View {
    @EnvironmentObject private var taskStatusReporter: TaskStatusReporter

    var body: some View {
        if taskStatusReporter.statuses.contains(where: { status in
            switch status.state {
            case .preparing, .running: true
            case .done: false
            }
        }) {
            StatusView()
                .font(.caption)
                .accessibilityIdentifier("preview-activity")
        }
    }
}

private struct SignedInDesktopView: View {
    let account: Account
    let applicationModel: MacApplicationModel
    @State private var projectContext: ProjectContext
    @State private var model: DesktopPreviewsModel
    @State private var navigation = DesktopNavigation()

    init(account: Account, applicationModel: MacApplicationModel) {
        self.account = account
        self.applicationModel = applicationModel
        let context = MacApplicationEnvironment.withValue {
            ProjectContext(scope: "\(AppServerEnvironmentService().url().absoluteString)/\(account.handle)")
        }
        _projectContext = State(initialValue: context)
        _model = State(initialValue: DesktopPreviewsModel(projectContext: context))
    }

    var body: some View {
        DesktopWorkspaceView(
            accountHandle: account.handle,
            model: model,
            navigation: $navigation,
            refresh: refresh,
            loadMore: loadMore
        )
        .task {
            do {
                try await projectContext.load()
            } catch {
                if !Task.isCancelled {
                    applicationModel.errorHandling.handle(error: error)
                }
            }
        }
        .task(id: projectContext.selectedFullHandle) {
            do {
                try await MacApplicationEnvironment.withValue { try await model.loadSelectedProject() }
            } catch {
                if !Task.isCancelled { applicationModel.errorHandling.handle(error: error) }
            }
        }
    }

    private func refresh() {
        applicationModel.errorHandling.fireAndHandleError {
            try await model.refresh()
        }
    }

    private func loadMore() async {
        await MacApplicationEnvironment.withValue {
            await model.loadMore()
        }
    }
}

struct DesktopPreviewRow: View {
    let preview: ServerPreview

    var body: some View {
        HStack(spacing: 12) {
            DesktopPreviewIcon(url: preview.iconURL)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(preview.displayName ?? "Preview")
                    .font(.headline)
                    .lineLimit(1)
                if let branch = preview.gitBranch {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 8) {
                    if let track = preview.track, !track.isEmpty {
                        Label(track, systemImage: "tag")
                            .lineLimit(1)
                    }
                    Text(preview.insertedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .contextMenu {
            Link("Open in Browser", destination: preview.url)
            Button("Copy Preview Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(preview.url.absoluteString, forType: .string)
            }
        }
    }
}

struct DesktopPreviewIcon: View {
    let url: URL

    var body: some View {
        CachedAsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}
