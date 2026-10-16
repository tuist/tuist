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
                        if viewModel.projects.isEmpty {
                            PreviewsEmptyStateView(
                                title: "No Tuist projects found",
                                buttonTitle: "Refresh",
                                isLoading: viewModel.isRefreshingProjects
                            ) {
                                errorHandling.fireAndHandleError {
                                    try await viewModel.refreshProjects()
                                }
                            }
                        } else if viewModel.previews.isEmpty {
                            PreviewsEmptyStateView(
                                title: "No previews found",
                                buttonTitle: "Refresh",
                                isLoading: viewModel.isRefreshingPreviews
                            ) {
                                errorHandling.fireAndHandleError {
                                    try await viewModel.refreshPreviews()
                                }
                            }
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
                            try await viewModel.refreshPreviews()
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
