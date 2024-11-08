
import SwiftUI

struct MenuHeader: View {
    var body: some View {
        HStack(alignment: .center) {
            Text("Tuist")
                .font(.headline)
                .fontWeight(.medium)

            Spacer()

            StatusView()
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .padding(.horizontal, 12)
    }
}
