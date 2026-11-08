#if os(iOS)
    import SwiftUI

    struct JamEmptyStateView: View {
        let archived: Bool
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(spacing: 20) {
                if !dynamicTypeSize.isAccessibilitySize {
                    ZStack {
                        ForEach(0 ..< 3) { index in
                            Circle()
                                .stroke(Color.accentColor.opacity(0.14 - Double(index) * 0.035), lineWidth: 1)
                                .frame(width: CGFloat(100 + index * 52), height: CGFloat(100 + index * 52))
                        }

                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.accentColor.opacity(0.08))
                            .frame(width: 94, height: 94)
                            .rotationEffect(.degrees(-12))

                        Image(systemName: archived ? "archivebox" : "bubble.left.and.bubble.right")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 94, height: 94)
                            .background(.background, in: RoundedRectangle(cornerRadius: 24))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                            }
                            .shadow(color: Color.accentColor.opacity(0.12), radius: 16, y: 8)
                    }
                    .frame(height: 220)
                    .accessibilityHidden(true)
                }

                VStack(spacing: 8) {
                    Text(LocalizedStringKey(archived ? "All clear, nothing archived" : "Big things start here"))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(LocalizedStringKey(archived
                            ? "Archived jams will live here. You can come back to them anytime."
                            : "Ask a question, explore an idea, or solve a problem with Tuist."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 16 : 32)
        }
    }
#endif
