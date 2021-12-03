import Foundation

public enum AutogenerationOptions: Hashable {
    public struct TestingOptions: OptionSet, Hashable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let parallelizable = TestingOptions(rawValue: 1 << 0)
        public static let randomExecutionOrdering = TestingOptions(rawValue: 1 << 1)
    }

    case disabled
    case enabled(TestingOptions)
}
