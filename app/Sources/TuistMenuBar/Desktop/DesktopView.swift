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

    private var selectedPreview: ServerPreview? {
        model.previews.first { $0.id == selectedPreviewID }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                ProjectSwitcher(context: projectContext)
                    .padding(16)
                List(DesktopSection.allCases, selection: $section) { section in
                    Label(section.rawValue, systemImage: section.systemImage)
                        .tag(section)
                }
                .listStyle(.sidebar)
                Divider()
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
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } content: {
            Group {
                if section == .previews {
                    previewList
                        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search loaded previews")
                } else {
                    home
                }
            }
            .navigationTitle(section?.rawValue ?? "Home")
            .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 500)
        } detail: {
            if let preview = selectedPreview,
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh Previews", systemImage: "arrow.clockwise", action: refresh)
                    .help("Refresh Previews (⌘R)")
                    .disabled(model.isLoading || projectContext.isLoading)
            }
            if let preview = selectedPreview {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: preview.url) {
                        Label("Share Preview", systemImage: "square.and.arrow.up")
                    }
                    .help("Share Preview")
                    .accessibilityIdentifier("share-preview")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Open in Browser", systemImage: "safari") {
                        NSWorkspace.shared.open(preview.url)
                    }
                    .help("Open Preview in Browser")
                    .accessibilityIdentifier("open-preview-in-browser")
                }
            }
        }
        .focusedSceneValue(\.desktopPreviewActions, DesktopPreviewActions(
            preview: selectedPreview,
            canRefresh: !model.isLoading && !projectContext.isLoading,
            refresh: refresh
        ))
        .onChange(of: model.selectedProjectFullHandle) {
            selectedPreviewID = nil
            model.clearFilters()
        }
        .onChange(of: model.filteredPreviews.map(\.id)) {
            if section == .previews, !model.filteredPreviews.contains(where: { $0.id == selectedPreviewID }) {
                selectedPreviewID = nil
            }
        }
        .onChange(of: section) {
            if section == .previews, !model.filteredPreviews.contains(where: { $0.id == selectedPreviewID }) {
                selectedPreviewID = nil
            }
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
        ScrollView {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if model.recentPreviews.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        ForEach(model.recentPreviews) { preview in
                            Button {
                                selectedPreviewID = preview.id
                            } label: {
                                DesktopPreviewRow(preview: preview)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .background(
                                        selectedPreviewID == preview.id ? Color.accentColor.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Divider()
                    Button("View All Previews", systemImage: "arrow.right") { section = .previews }
                        .buttonStyle(.link)
                }
                .padding(8)
            } label: {
                Label("Recent previews", systemImage: "app.badge")
            }
            .padding(16)
        }
    }

    private var previewList: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Track", selection: $model.trackFilter) {
                    Text("All Tracks").tag(PreviewTrackFilter.all)
                    Text("No Track").tag(PreviewTrackFilter.unassigned)
                    Divider()
                    ForEach(model.availableTracks, id: \.self) { track in
                        Text(track).tag(PreviewTrackFilter.track(track))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("preview-track-filter")
                .help("Filter the loaded previews by release track")
                .disabled(model.isLoading || projectContext.isLoading)
                Spacer(minLength: 8)
                Button("Clear Filters") { model.clearFilters() }
                    .disabled(!model.hasActiveFilters)
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            List(selection: $selectedPreviewID) {
                ForEach(model.filteredPreviews) { preview in
                    DesktopPreviewRow(preview: preview)
                        .tag(preview.id)
                }
            }
            .listStyle(.inset)
            .overlay { emptyState }
            Divider()
            HStack {
                Text("\(model.filteredPreviews.count) of \(model.previews.count) loaded")
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isLoadingMore {
                    ProgressView().controlSize(.small)
                } else if model.hasMorePreviews {
                    Button("Load More") {
                        applicationModel.errorHandling.fireAndHandleError {
                            try await model.loadMore()
                        }
                    }
                    .accessibilityIdentifier("load-more-previews")
                }
            }
            .font(.caption)
            .controlSize(.small)
            .padding(12)
        }
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
            ContentUnavailableView {
                Label("No Matching Previews", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Try another search or track, or load more previews.")
            } actions: {
                Button("Clear Filters") { model.clearFilters() }
            }
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
