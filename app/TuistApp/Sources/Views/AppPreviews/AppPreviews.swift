import SwiftUI

struct AppPreviews: View {
    private let columns = Array(repeating: GridItem(.fixed(44), spacing: 14), count: 5)
    @State var viewModel: AppPreviewsViewModel
    @EnvironmentObject var errorHandling: ErrorHandling
    @EnvironmentObject var appCredentialsService: AppCredentialsService

    init(
        viewModel: AppPreviewsViewModel
    ) {
        self.viewModel = viewModel
    }

    var body: some View {
        Panel {
            Group {
                if viewModel.appPreviews.isEmpty {
                    AppPreviewsEmptyStateView()
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(viewModel.appPreviews) { appPreview in
                            Button {
                                errorHandling.fireAndHandleError {
                                    try await viewModel.launchAppPreview(appPreview)
                                }
                            } label: {
                                AppPreviewTile(appPreview: appPreview)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .padding([.top, .horizontal], 16)
            .padding(.bottom, 12)
        }
        .onAppear {
            viewModel.loadAppPreviewsFromCache()
            errorHandling.fireAndHandleError(viewModel.onAppear)
        }
        .onChange(
            of: appCredentialsService.authenticationState
        ) {
            errorHandling.fireAndHandleError(viewModel.onAuthenticationStateChanged)
        }
    }
}
