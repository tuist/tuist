import Foundation
import Library

internal class InternalFrameworkClass: FrameworkProtocol {
    internal let text: String
    required internal init() {
        text = Library().text
    }
}
