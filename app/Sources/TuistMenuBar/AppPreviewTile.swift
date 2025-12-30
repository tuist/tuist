import SwiftUI

struct AppPreviewTile: View {
    let appPreview: AppPreview

    var body: some View {
        VStack(spacing: 4) {
            CachedAsyncImage(url: appPreview.iconURL) { image in
                image
                    .pinnedApplicationImageStyle()
            } placeholder: {
                Image("AppIconPlaceholder")
                    .pinnedApplicationImageStyle()
            }

            Text(appPreview.displayName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 60)
                .fixedSize()
        }
    }
}

extension Image {
    fileprivate func pinnedApplicationImageStyle() -> some View {
        resizable()
            .scaledToFit()
            .frame(width: 44, height: 44)
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
    }
}
