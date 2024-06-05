import Foundation

public enum AutogenerationOptions: Hashable {
    case disabled
    case enabled(TestingOptions)
}
