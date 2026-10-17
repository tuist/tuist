import Nuke
import SwiftUI
import TuistErrorHandling
import TuistNoora
import TuistProjects
import TuistServer

public struct PreviewsView: View {
    @EnvironmentObject var errorHandling: ErrorHandling
    private let viewModel: PreviewsViewModel
    @State private var searchText = ""
    @State private var navigationPath = NavigationPath()
    @Binding private var pendingPreview: DeeplinkPreview?
    private let imagePrefetcher = ImagePrefetcher()

    public init(
        viewModel: PreviewsViewModel,
        pendingPreview: Binding<DeeplinkPreview?> = .constant(nil)
    ) {
        self.viewModel = viewModel
        _pendingPreview = pendingPreview
    }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isInitialLoading {
                    VStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.2)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Noora.Colors.surfaceBackgroundPrimary)
                } else {
                    List {
                        if viewModel.selectedProject != nil {
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
                            .listRowInsets(
                                EdgeInsets(top: 0, leading: Noora.Spacing.spacing7, bottom: 0, trailing: Noora.Spacing.spacing7)
                            )
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
                                PreviewRowView(preview: preview) {
                                    guard let project = viewModel.selectedProject else { return }
                                    navigationPath.append(PreviewDestination(preview: preview, fullHandle: project.fullName))
                                }
                                .listRowSeparator(.hidden)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: 0,
                                        leading: Noora.Spacing.spacing7,
                                        bottom: 0,
                                        trailing: Noora.Spacing.spacing7
                                    )
                                )
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
                            if !Task.isCancelled { errorHandling.handle(error: error) }
                        }
                    }
                }
            }
            .navigationTitle("Previews")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ProjectSwitcher(context: viewModel.projectContext)
                }
            }
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
            .onChange(of: viewModel.selectedProject?.fullName) {
                searchText = ""
            }
            .background(Noora.Colors.surfaceBackgroundPrimary)
            .navigationDestination(for: PreviewDestination.self) { destination in
                PreviewView(preview: destination.preview, fullHandle: destination.fullHandle)
            }
            .navigationDestination(for: DeeplinkPreview.self) { deeplink in
                PreviewView(previewId: deeplink.previewId, fullHandle: deeplink.fullHandle)
            }
            .onChange(of: pendingPreview, initial: true) {
                guard let preview = pendingPreview else { return }
                navigationPath = NavigationPath()
                navigationPath.append(preview)
                pendingPreview = nil
            }
        }
    }

    private var hasActiveFilters: Bool {
        viewModel.selectedTrack != nil || !viewModel.searchQuery.isEmpty
    }

    private func trackChip(_ title: String, track: String?, count: Int?) -> some View {
        let isSelected = track.map { viewModel.selectedTrack?.caseInsensitiveCompare($0) == .orderedSame }
            ?? (viewModel.selectedTrack == nil)
        return Button {
            selectTrack(track)
        } label: {
            HStack(spacing: Noora.Spacing.spacing2) {
                Text(title)
                    .foregroundStyle(isSelected ? .white : Noora.Colors.surfaceLabelPrimary)
                if let count {
                    Text(count.formatted())
                        .foregroundStyle(isSelected ? .white.opacity(0.65) : Noora.Colors.surfaceLabelSecondary)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, Noora.Spacing.spacing4)
            .padding(.vertical, Noora.Spacing.spacing2)
            .background(
                isSelected ? Noora.Colors.buttonPrimaryBackground : Noora.Colors.surfaceBackgroundTertiary,
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(Noora.Colors.neutralGray24Alpha, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(track ?? "All tracks")
        .accessibilityValue(count.map { "\($0) previews" } ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(track.map { "preview-track-\($0)" } ?? "preview-track-all")
    }

    private func selectTrack(_ track: String?) {
        errorHandling.fireAndHandleError {
            try await viewModel.selectTrack(track)
        }
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
