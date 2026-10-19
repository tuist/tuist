#if os(iOS)
    import SwiftUI
    import TuistErrorHandling
    import TuistHome
    import TuistNoora
    import TuistPreviews
    import TuistProjects

    struct HomeView: View {
        @EnvironmentObject private var errorHandling: ErrorHandling
        private let viewModel: PreviewsViewModel
        @State private var navigationPath = NavigationPath()
        @State private var activityModel: HomeActivityModel
        private let onSeeAllPreviews: () -> Void

        init(viewModel: PreviewsViewModel, onSeeAllPreviews: @escaping () -> Void) {
            self.viewModel = viewModel
            self.onSeeAllPreviews = onSeeAllPreviews
            _activityModel = State(initialValue: HomeActivityModel(projectContext: viewModel.projectContext))
        }

        var body: some View {
            NavigationStack(path: $navigationPath) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HomeActivityView(model: activityModel) { errorHandling.handle(error: $0) }
                        recentPreviewsCard
                    }
                    .padding(20)
                }
                .scrollBounceBehavior(.always)
                .background(Noora.Colors.surfaceBackgroundPrimary)
                .navigationTitle("Home")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        ProjectSwitcher(context: viewModel.projectContext)
                    }
                }
                .refreshable {
                    async let activity: Void = activityModel.load(force: true)
                    do {
                        try await viewModel.refreshProjects()
                    } catch {
                        if !Task.isCancelled { errorHandling.handle(error: error) }
                    }
                    await activity
                }
                .navigationDestination(for: PreviewDestination.self) { destination in
                    PreviewView(preview: destination.preview, fullHandle: destination.fullHandle)
                }
            }
        }

        private var recentPreviewsCard: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "app.badge")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent previews")
                            .font(.headline)
                        Text("Latest shared apps")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)

                if viewModel.isInitialLoading {
                    ProgressView("Loading previews…")
                        .frame(maxWidth: .infinity)
                        .padding(24)
                } else if let selectedProject = viewModel.selectedProject {
                    if viewModel.recentPreviews.isEmpty {
                        cardMessage("No previews yet", isLoading: viewModel.isRefreshingPreviews, action: refresh)
                    } else {
                        ForEach(viewModel.recentPreviews) { preview in
                            PreviewRowView(preview: preview, style: .compact) {
                                navigationPath.append(
                                    PreviewDestination(preview: preview, fullHandle: selectedProject.fullName)
                                )
                            }
                        }
                    }
                } else {
                    cardMessage("No Tuist projects found", isLoading: viewModel.isRefreshingProjects) {
                        errorHandling.fireAndHandleError {
                            try await viewModel.refreshProjects()
                        }
                    }
                }

                Button(action: onSeeAllPreviews) {
                    HStack {
                        Text("View all previews")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Noora.Colors.surfaceBackgroundTertiary, in: RoundedRectangle(cornerRadius: 20))
        }

        private func cardMessage(_ title: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
            VStack(spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if isLoading {
                    ProgressView()
                } else {
                    Button("Refresh", action: action)
                        .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }

        private func refresh() {
            errorHandling.fireAndHandleError {
                try await viewModel.refreshPreviews()
            }
        }
    }
#endif
