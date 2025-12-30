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
    @State private var searchText = ""
    @State private var navigationPath = NavigationPath()
    @State private var pressedPreviewId: String?
    private let imagePrefetcher = ImagePrefetcher()

    public init() {}

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
                            .listRowBackground(Noora.Colors.surfaceBackgroundPrimary)
                        }

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
                                PreviewRowView(
                                    preview: preview,
                                    navigationPath: $navigationPath,
                                    pressedPreviewId: $pressedPreviewId
                                )
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
                        errorHandling.fireAndHandleError {
                            try await viewModel.refreshPreviews()
                        }
                    }
                }
            }
            .onAppear {
                // When deleting an account, there's a bug when onAppear is called even when already logged out.
                // This should never happen due to the check in TuistApp.swift, but it seems there's a race condition in the
                // SwiftUI lifecycle
                guard case .loggedIn = authenticationService.authenticationState else { return }
                errorHandling.fireAndHandleError {
                    try await viewModel.onAppear()
                }
            }
            .navigationTitle("Previews")
            .navigationBarTitleDisplayMode(.automatic)
            .background(Noora.Colors.surfaceBackgroundPrimary)
            .navigationDestination(for: ServerPreview.self) { preview in
                PreviewView(preview: preview, fullHandle: viewModel.selectedProject!.fullName)
            }
            .navigationDestination(for: DeeplinkPreview.self) { deeplink in
                PreviewView(previewId: deeplink.previewId, fullHandle: deeplink.fullHandle)
            }
            .onOpenURL { url in
                handleOpenURL(url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                guard let url = userActivity.webpageURL else { return }
                handleOpenURL(url)
            }
        }
    }

    private func handleOpenURL(_ url: URL) {
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 4,
              pathComponents[2] == "previews"
        else { return }

        let previewId = pathComponents[3]
        let fullHandle = "\(pathComponents[0])/\(pathComponents[1])"

        let deeplink = DeeplinkPreview(previewId: previewId, fullHandle: fullHandle)
        navigationPath.append(deeplink)
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
