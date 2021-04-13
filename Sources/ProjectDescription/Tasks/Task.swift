import Foundation

public struct Task {
    public let name: String
    public let task: () throws -> ()
    
    public static func task(_ name: String, task: @escaping () throws -> ()) -> Task {
        .init(
            name: name,
            task: task
        )
    }
}
