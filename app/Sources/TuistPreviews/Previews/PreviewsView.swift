import SwiftUI
import TuistErrorHandling

public struct PreviewsView: View {
    @EnvironmentObject var errorHandling: ErrorHandling
    @State var viewModel = PreviewsViewModel()

    public init() {}

    public var body: some View {
        List(viewModel.previews) { preview in
            HStack {
                Text(preview.displayName ?? "App")
                Button("Install", action: {
                    let url =
                        URL(string: "itms-services://?action=download-manifest&url=\(preview.url.absoluteString)/manifest.plist")!
                    UIApplication.shared.open(url)
                })
            }
        }
        .onAppear {
            errorHandling.fireAndHandleError {
                try await viewModel.onAppear()
            }
        }
    }
}
