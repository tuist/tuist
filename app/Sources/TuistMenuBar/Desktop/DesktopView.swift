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
            switch authenticationService.authenticationState {
            case let .loggedIn(account, server):
                SignedInDesktopView(account: account, applicationModel: applicationModel)
                    .id("\(server?.url.absoluteString ?? "hosted")/\(account.handle)")
            case .loggedOut:
                DesktopLoginView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if case .loggedIn = authenticationService.authenticationState {
                HStack {
                    StatusView()
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .macApplicationEnvironment(applicationModel)
        .task {
            do {
                try await applicationModel.loadDevices()
            } catch {
                applicationModel.errorHandling.handle(error: error)
            }
        }
    }
}

private enum DesktopSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case previews = "Previews"

    var id: String { rawValue }
    var systemImage: String { self == .home ? "house" : "app.dashed" }
}

private struct SignedInDesktopView: View {
    let account: Account
    let applicationModel: MacApplicationModel
    @State private var projectContext: ProjectContext
    @State private var model: DesktopPreviewsModel
    @State private var section: DesktopSection? = .home
    @State private var selectedPreviewID: String?

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
        NavigationSplitView {
            List(DesktopSection.allCases, selection: $section) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
            .safeAreaInset(edge: .top, spacing: 0) {
                ProjectSwitcher(context: projectContext)
                    .padding()
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Label(account.handle, systemImage: "person.crop.circle")
                        .lineLimit(1)
                    Spacer()
                    SettingsLink {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.borderless)
                    .help("Settings")
                }
                .foregroundStyle(.secondary)
                .padding()
            }
        } content: {
            Group {
                if section == .previews {
                    previewList
                        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Filter previews")
                } else {
                    home
                }
            }
            .navigationTitle(section?.rawValue ?? "Home")
            .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 500)
            .toolbar {
                ToolbarItem {
                    Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(model.isLoading || projectContext.isLoading)
                }
            }
        } detail: {
            if let preview = model.previews.first(where: { $0.id == selectedPreviewID }),
               let fullHandle = model.selectedProjectFullHandle
            {
                DesktopPreviewDetail(preview: preview, fullHandle: fullHandle)
                    .id("\(fullHandle)/\(preview.id)")
            } else {
                ContentUnavailableView(
                    "Select a Preview",
                    systemImage: "app.dashed",
                    description: Text("Choose a preview to see its details and run it on a device.")
                )
            }
        }
        .onChange(of: model.selectedProjectFullHandle) {
            selectedPreviewID = nil
        }
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

    private var home: some View {
        List(selection: $selectedPreviewID) {
            Section {
                ForEach(model.recentPreviews) { preview in
                    DesktopPreviewRow(preview: preview)
                        .tag(preview.id)
                }
            } header: {
                HStack {
                    Text("Recent previews")
                    Spacer()
                    Button("See All") { section = .previews }
                        .buttonStyle(.borderless)
                }
            }
        }
        .overlay { emptyState }
    }

    private var previewList: some View {
        List(selection: $selectedPreviewID) {
            ForEach(model.filteredPreviews) { preview in
                DesktopPreviewRow(preview: preview)
                    .tag(preview.id)
            }
            if model.hasMorePreviews {
                HStack {
                    Spacer()
                    if model.isLoadingMore {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Load More Previews") {
                            applicationModel.errorHandling.fireAndHandleError {
                                try await model.loadMore()
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .overlay { emptyState }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.isLoading || projectContext.isLoading, model.previews.isEmpty {
            ProgressView("Loading previews…")
        } else if let message = model.errorMessage ?? projectContext.errorMessage, model.previews.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Previews", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again", action: refresh)
            }
        } else if model.projects.isEmpty {
            ContentUnavailableView(
                "No Projects",
                systemImage: "folder",
                description: Text("Projects you have access to will appear here.")
            )
        } else if model.previews.isEmpty {
            ContentUnavailableView(
                "No Previews",
                systemImage: "app.dashed",
                description: Text("Share a preview with Tuist to see it here.")
            )
        } else if section == .previews, model.filteredPreviews.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
                .allowsHitTesting(false)
        }
    }

    private func refresh() {
        applicationModel.errorHandling.fireAndHandleError {
            try await model.refresh()
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
                }
                Text(preview.insertedAt, style: .relative)
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
