import SwiftUI

struct AppPreviews: View {
    private let columns = Array(repeating: GridItem(.fixed(44), spacing: 14), count: 5)
    @State var viewModel: AppPreviewsViewModel
    @EnvironmentObject var errorHandling: ErrorHandling

    init(
        viewModel: AppPreviewsViewModel
    ) {
        self.viewModel = viewModel
    }

    var body: some View {
        Panel {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(viewModel.appPreviews) { appPreview in
                    Button {
                        Task {
                            do {
                                try await viewModel.launchAppPreview(appPreview)
                            } catch {
                                errorHandling.handle(error: error)
                            }
                        }
                    } label: {
                        AppPreviewTile(appPreview: appPreview)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .padding([.top, .horizontal], 16)
            .padding(.bottom, 12)
        }
        .onAppear {
            viewModel.loadAppPreviewsFromCache()

            Task {
                do {
                    try await viewModel.onAppear()
                } catch {
                    errorHandling.handle(error: error)
                }
            }
        }
    }
}
