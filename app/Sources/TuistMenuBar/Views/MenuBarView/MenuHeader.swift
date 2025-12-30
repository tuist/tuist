
import SwiftUI

struct MenuHeader: View {
    let accountHandle: String?

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading) {
                Text("Tuist")
                    .font(.headline)
                    .fontWeight(.medium)
                Text(accountHandle ?? "Logged out")
                    .font(.caption)
                    .fontWeight(.light)
                    .foregroundColor(.gray)
            }

            Spacer()

            StatusView()
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .padding(.horizontal, 12)
    }
}
