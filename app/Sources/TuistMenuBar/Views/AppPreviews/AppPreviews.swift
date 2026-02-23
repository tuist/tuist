import SwiftUI

struct AppPreviews: View {
    @State var viewModel: AppPreviewsViewModel
    @EnvironmentObject var errorHandling: ErrorHandling

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
                        .padding([.top, .horizontal], 16)
                        .padding(.bottom, 12)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
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
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .onAppear {
            viewModel.loadAppPreviewsFromCache()
            errorHandling.fireAndHandleError(viewModel.onAppear)
        }
    }
}
