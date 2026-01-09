import SwiftUI

public struct LogoImage: View {
    public init() { /* empty init */ }
    public var body: some View {
        VStack {
            Spacer()
            Image(.tuistLogo)
                .resizable()
            Spacer()
        }
    }
}

#Preview {
    LogoImage()
        .frame(width: 200, height: 200)
}
