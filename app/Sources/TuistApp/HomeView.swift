#if os(iOS)
    import SwiftUI
    import TuistErrorHandling
    import TuistNoora
    import TuistPreviews
    import TuistProjects
    import TuistServer

    struct HomeView: View {
        @EnvironmentObject private var errorHandling: ErrorHandling
        private let viewModel: PreviewsViewModel
        @State private var navigationPath = NavigationPath()
        private let onSeeAllPreviews: () -> Void

        init(viewModel: PreviewsViewModel, onSeeAllPreviews: @escaping () -> Void) {
            self.viewModel = viewModel
            self.onSeeAllPreviews = onSeeAllPreviews
        }

        var body: some View {
            NavigationStack(path: $navigationPath) {
                List {
                    Section {
                        if viewModel.isInitialLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else if let selectedProject = viewModel.selectedProject {
                            if viewModel.recentPreviews.isEmpty {
                                PreviewsEmptyStateView(
                                    title: "No previews found",
                                    buttonTitle: "Refresh",
                                    isLoading: viewModel.isRefreshingPreviews
                                ) {
                                    refresh()
                                }
                            } else {
                                ForEach(viewModel.recentPreviews) { preview in
                                    PreviewRowView(preview: preview) {
                                        navigationPath.append(
                                            PreviewDestination(preview: preview, fullHandle: selectedProject.fullName)
                                        )
                                    }
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                                }
                            }
                        } else {
                            PreviewsEmptyStateView(
                                title: "No Tuist projects found",
                                buttonTitle: "Refresh",
                                isLoading: viewModel.isRefreshingProjects
                            ) {
                                errorHandling.fireAndHandleError {
                                    try await viewModel.refreshProjects()
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Recent previews")
                                .font(.headline)
                                .foregroundStyle(Noora.Colors.surfaceLabelPrimary)
                            Spacer()
                            Button("See all", action: onSeeAllPreviews)
                                .textCase(nil)
                        }
                    }
                    .listRowBackground(Noora.Colors.surfaceBackgroundPrimary)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Noora.Colors.surfaceBackgroundPrimary)
                .navigationTitle("Home")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        ProjectSwitcher(context: viewModel.projectContext)
                    }
                }
                .refreshable {
                    do {
                        try await viewModel.refreshProjects()
                    } catch {
                        if !Task.isCancelled { errorHandling.handle(error: error) }
                    }
                }
                .navigationDestination(for: PreviewDestination.self) { destination in
                    PreviewView(preview: destination.preview, fullHandle: destination.fullHandle)
                }
            }
        }

        private func refresh() {
            errorHandling.fireAndHandleError {
                try await viewModel.refreshPreviews()
            }
        }
    }
#endif
