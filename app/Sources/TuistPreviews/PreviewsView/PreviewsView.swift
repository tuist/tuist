import Nuke
import SwiftUI
import TuistAuthentication
import TuistErrorHandling
import TuistNoora
import TuistServer

public struct PreviewsView: View {
    @EnvironmentObject var errorHandling: ErrorHandling
    @EnvironmentObject private var authenticationService: AuthenticationService
    @State var viewModel = PreviewsViewModel()
    @State private var selectedPreview: DeeplinkPreview?
    @State private var preferredCompactColumn = NavigationSplitViewColumn.sidebar
    @State private var searchText = ""
    private let imagePrefetcher = ImagePrefetcher()
    private let rowInsets = EdgeInsets(top: 0, leading: Noora.Spacing.spacing7, bottom: 0, trailing: Noora.Spacing.spacing7)

    public init() {}

    public var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            Group {
                if viewModel.isInitialLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Noora.Colors.surfaceBackgroundPrimary)
                } else {
                    List(selection: $selectedPreview) {
                        if let selectedProject = viewModel.selectedProject {
                            HStack(spacing: Noora.Spacing.spacing3) {
                                Text("Apps in")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                    .foregroundColor(Noora.Colors.surfaceLabelPrimary)
                                    .fixedSize()

                                NooraDropdown<ServerProject>(
                                    options: viewModel.projects,
                                    currentOption: selectedProject,
                                    cornerRadius: Noora.CornerRadius.max,
                                    selectedOption: { project in
                                        errorHandling.fireAndHandleError {
                                            try await viewModel.selectProject(project)
                                        }
                                    }
                                )
                                .accessibilityIdentifier("preview-project-selector")
                            }
                            .padding(.vertical, Noora.Spacing.spacing4)
                            .listRowSeparator(.hidden)
                            .listRowInsets(rowInsets)
                            .listRowBackground(Noora.Colors.surfaceBackgroundPrimary)

                            VStack(alignment: .leading, spacing: Noora.Spacing.spacing3) {
                                Text("Tracks")
                                    .font(.headline.weight(.medium))
                                    .foregroundColor(Noora.Colors.surfaceLabelPrimary)

                                ScrollView(.horizontal) {
                                    HStack(spacing: Noora.Spacing.spacing3) {
                                        trackChip("All", track: nil, count: viewModel.totalPreviewCount)
                                        ForEach(viewModel.trackOptions, id: \.self) { track in
                                            trackChip(track, track: track, count: viewModel.previewCount(for: track))
                                        }
                                    }
                                    .padding(.vertical, Noora.Spacing.spacing1)
                                }
                                .scrollIndicators(.hidden)
                            }
                            .padding(.bottom, Noora.Spacing.spacing4)
                            .listRowSeparator(.hidden)
                            .listRowInsets(rowInsets)
                            .listRowBackground(Noora.Colors.surfaceBackgroundPrimary)

                            if !viewModel.isTrackSelectionSupported {
                                Text("Update your self-hosted Tuist server to select a track.")
                                    .font(.footnote)
                                    .foregroundStyle(Noora.Colors.surfaceLabelSecondary)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(
                                        EdgeInsets(
                                            top: 0,
                                            leading: Noora.Spacing.spacing7,
                                            bottom: Noora.Spacing.spacing4,
                                            trailing: Noora.Spacing.spacing7
                                        )
                                    )
                                    .listRowBackground(Noora.Colors.surfaceBackgroundPrimary)
                            }
                        }

                        if viewModel.projects.isEmpty {
                            PreviewsEmptyStateView(
                                title: "No Tuist projects found",
                                subtitle: "Pull down to refresh your projects."
                            )
                        } else if viewModel.isLoadingPreviews, viewModel.previews.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Noora.Colors.surfaceBackgroundPrimary)
                        } else if viewModel.previews.isEmpty {
                            PreviewsEmptyStateView(
                                title: hasActiveFilters ? "No previews match your filters" : "No previews found",
                                subtitle: hasActiveFilters
                                    ? "Try a different search or select another track."
                                    : "Pull down to refresh your previews."
                            )
                        } else {
                            ForEach(viewModel.previews) { preview in
                                NavigationLink(value: destination(for: preview)) {
                                    PreviewRowView(preview: preview)
                                }
                                .accessibilityIdentifier("preview-row-\(preview.id)")
                                .listRowSeparator(.hidden)
                                .listRowInsets(rowInsets)
                                .onAppear {
                                    if preview.id == viewModel.previews.last?.id {
                                        errorHandling.fireAndHandleError {
                                            try await viewModel.loadMorePreviews()
                                        }
                                    }

                                    preloadUpcomingImages(for: preview)
                                }
                                .listRowBackground(Noora.Colors.surfaceBackgroundPrimary)
                            }
                        }
                        if viewModel.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                                Spacer()
                            }
                            .listRowBackground(Noora.Colors.surfaceBackgroundPrimary)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        do {
                            if viewModel.projects.isEmpty {
                                try await viewModel.refreshProjects()
                            } else {
                                try await viewModel.refreshPreviews()
                            }
                        } catch {
                            errorHandling.handle(error: error)
                        }
                    }
                }
            }
            .onAppear {
                // When deleting an account, there's a bug when onAppear is called even when already logged out.
                // This should never happen due to the check in TuistApp.swift, but it seems there's a race condition in the
                // SwiftUI lifecycle
                guard case .loggedIn = authenticationService.authenticationState,
                      viewModel.isInitialLoading
                else { return }
                errorHandling.fireAndHandleError {
                    try await viewModel.onAppear()
                }
            }
            .navigationTitle("Previews")
            .navigationBarTitleDisplayMode(.automatic)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            .task(id: searchText) {
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    try Task.checkCancellation()
                    try await viewModel.searchPreviews(searchText)
                } catch is CancellationError {
                } catch {
                    guard !Task.isCancelled else { return }
                    errorHandling.handle(error: error)
                }
            }
            .onChange(of: viewModel.selectedProject?.fullName) { oldValue, _ in
                searchText = viewModel.searchQuery
                if oldValue != nil {
                    clearSelection()
                }
            }
            .background(Noora.Colors.surfaceBackgroundPrimary)
        } detail: {
            if let selectedPreview {
                Group {
                    if let preview = viewModel.previews.first(where: { $0.id == selectedPreview.previewId }),
                       viewModel.selectedProject?.fullName == selectedPreview.fullHandle
                    {
                        PreviewView(preview: preview, fullHandle: selectedPreview.fullHandle, onDelete: didDeletePreview)
                    } else {
                        PreviewView(
                            previewId: selectedPreview.previewId,
                            fullHandle: selectedPreview.fullHandle,
                            onDelete: didDeletePreview
                        )
                    }
                }
                .id(selectedPreview)
            } else {
                ContentUnavailableView(
                    "Select a preview",
                    systemImage: "iphone",
                    description: Text("Choose an app to see its details.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onOpenURL { url in
            handleOpenURL(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
            guard let url = userActivity.webpageURL else { return }
            handleOpenURL(url)
        }
    }

    private func didDeletePreview() {
        clearSelection()
        errorHandling.fireAndHandleError {
            try await viewModel.refreshPreviews()
        }
    }

    private func clearSelection() {
        selectedPreview = nil
        preferredCompactColumn = .sidebar
    }

    private func destination(for preview: ServerPreview) -> DeeplinkPreview? {
        guard let project = viewModel.selectedProject else { return nil }
        return DeeplinkPreview(previewId: preview.id, fullHandle: project.fullName)
    }

    private var hasActiveFilters: Bool {
        viewModel.selectedTrack != nil || !viewModel.searchQuery.isEmpty
    }

    private func trackChip(_ title: String, track: String?, count: Int?) -> some View {
        PreviewTrackChip(title: title, track: track, count: count, selectedTrack: viewModel.selectedTrack) {
            selectTrack(track)
        }
    }

    private func selectTrack(_ track: String?) {
        errorHandling.fireAndHandleError {
            try await viewModel.selectTrack(track)
        }
    }

    private func handleOpenURL(_ url: URL) {
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 4,
              pathComponents[2] == "previews"
        else { return }

        let previewId = pathComponents[3]
        let fullHandle = "\(pathComponents[0])/\(pathComponents[1])"

        selectedPreview = DeeplinkPreview(previewId: previewId, fullHandle: fullHandle)
        preferredCompactColumn = .detail
    }

    private func preloadUpcomingImages(for currentPreview: ServerPreview) {
        guard let currentIndex = viewModel.previews.firstIndex(where: { $0.id == currentPreview.id }) else { return }

        let preloadRange = 5
        let startIndex = currentIndex + 1
        let endIndex = min(startIndex + preloadRange, viewModel.previews.count)

        imagePrefetcher.startPrefetching(
            with: viewModel.previews[startIndex ..< endIndex].map(\.iconURL)
        )
    }
}
