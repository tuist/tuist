import Foundation
import SwiftUI
import TuistNoora
import TuistServer

struct PreviewRunButton: View {
    @State private var isLoading = false
    @Environment(\.openURL) private var openURL
    var isDisabled: Bool {
        !preview.appBuilds
            .contains(where: { $0.type == .ipa && $0.supportedPlatforms.contains(.device(.iOS)) })
    }

    let preview: ServerPreview

    var body: some View {
        if isDisabled {
            EmptyView()
        } else {
            NooraButton(
                title: "Run",
                isLoading: isLoading
            ) {
                run()
            }
            .onTapGesture {
                // We're using tap gesture instead of the Button action to take precedence over navigation tap gesture needed in
                // PreviewsView
                run()
            }
        }
    }

    private func run() {
        guard !isDisabled else { return }
        isLoading = true
        openURL(preview.deviceURL)

        Task {
            // It takes some time for the alert to install the app to appear
            // We don't have a way to hook into the alert displaying, so we're using a hardcoded value to signal
            // that
            // something was triggered.
            try await Task.sleep(for: .seconds(2))
            isLoading = false
        }
    }
}
