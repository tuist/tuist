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
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 14) {
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
                        .padding(.bottom, 8)
                        .padding([.top, .horizontal], 12)
                    }
                    .frame(minWidth: 250, maxWidth: 300)
                    .padding(4)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            viewModel.loadAppPreviewsFromCache()
            errorHandling.fireAndHandleError(viewModel.onAppear)
        }
    }
}
