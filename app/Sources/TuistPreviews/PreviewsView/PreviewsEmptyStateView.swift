import SwiftUI
import TuistNoora

struct PreviewsEmptyStateView: View {
    let title: String
    let subtitle: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "iphone")
        } description: {
            Text(subtitle)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Noora.Colors.surfaceBackgroundPrimary)
    }
}
