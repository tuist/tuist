import SwiftUI

struct ThisMacRow: View {
    let selected: Bool
    let onSelected: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            ZStack {
                Circle()
                    .fill(selected ? .blue : .gray.opacity(0.4))

                Image(systemName: "macbook")
                    .foregroundColor(
                        selected ? TuistMenuBarAsset.Assets.light.swiftUIColor : TuistMenuBarAsset.Assets.dark
                            .swiftUIColor
                    )
            }
            .frame(width: 24, height: 24)
            Text("This Mac")
                .font(.title3)
            Spacer()
        }
        .menuItemStyle()
        .onTapGesture {
            onSelected()
        }
    }
}
