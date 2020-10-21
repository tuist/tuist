import Foundation

public struct TestPlanList: Equatable, Codable {
    public let `default`: Path
    public let other: [Path]

    public init(default: Path, other: [Path] = []) {
        self.default = `default`
        self.other = other
    }
}
