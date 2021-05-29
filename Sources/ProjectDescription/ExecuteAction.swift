import Foundation

public struct ExecutionAction: Equatable, Codable {
    public let title: String
    public let scriptText: String
    public let target: TargetReference?

    public init(title: String = "Run Script", scriptText: String, target: TargetReference? = nil) {
        self.title = title
        self.scriptText = scriptText
        self.target = target
    }
}
