import Nuke
import SwiftUI
import TuistErrorHandling
import TuistNoora
import TuistServer

public struct PreviewsView: View {
    @EnvironmentObject var errorHandling: ErrorHandling
    @State var viewModel = PreviewsViewModel()
    @State private var searchText = ""
    private let imagePrefetcher = ImagePrefetcher()

    public init() {}

    public var body: some View {
        List {
            if let selectedProject = viewModel.selectedProject {
                HStack(spacing: Noora.Spacing.spacing3) {
                    Text("Apps in")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(Noora.Colors.surfaceLabelPrimary)

                    NooraDropdown<ServerProject>(
                        options: viewModel.projects,
                        currentOption: selectedProject,
                        selectedOption: { project in
                            errorHandling.fireAndHandleError {
                                try await viewModel.selectProject(project)
                            }
                        }
                    )
                }
                .padding(.vertical, Noora.Spacing.spacing4)
                .listRowSeparator(.hidden)
                .listRowInsets(
                    EdgeInsets(top: 0, leading: Noora.Spacing.spacing7, bottom: 0, trailing: Noora.Spacing.spacing7)
                )
            }

            ForEach(viewModel.previews) { preview in
                PreviewRowView(preview: preview)
                    .listRowSeparator(.hidden)
                    .listRowInsets(
                        EdgeInsets(top: 0, leading: Noora.Spacing.spacing7, bottom: 0, trailing: Noora.Spacing.spacing7)
                    )
                    .onAppear {
                        if preview.id == viewModel.previews.last?.id {
                            errorHandling.fireAndHandleError {
                                try await viewModel.loadMorePreviews()
                            }
                        }

                        preloadUpcomingImages(for: preview)
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
            }
        }
        .listStyle(.plain)
        .refreshable {
            errorHandling.fireAndHandleError {
                try await viewModel.refreshPreviews()
            }
        }
        .onAppear {
            errorHandling.fireAndHandleError {
                try await viewModel.onAppear()
            }
        }
        .navigationTitle("Previews")
        .navigationBarTitleDisplayMode(.automatic)
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
