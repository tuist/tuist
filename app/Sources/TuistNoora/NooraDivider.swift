import Foundation
import SwiftUI

public struct NooraDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(Color(light: Noora.Colors.neutralLight400, dark: Noora.Colors.neutralDark900))
            .frame(height: 1)
    }
}
