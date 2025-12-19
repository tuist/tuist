import ResourcesFramework
import SwiftUI

struct TestView: View {
    var body: some View {
        VStack {
            Button("Click to read file from bundle") {
                text = readFileFromBundle()
            }
            Text(text)
        }
    }

    @State var text = "-"
}

#Preview {
    TestView()
}
