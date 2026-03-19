import SwiftUI

public struct GreetingView: View {
    public init() {}

    public var body: some View {
        VStack {
            Text("greeting_hello", bundle: .module)
            Text("greeting_welcome", bundle: .module)
        }
    }
}
