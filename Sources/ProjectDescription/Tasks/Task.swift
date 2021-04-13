import Foundation

public struct Task: Codable {
    public let name: String
    public let task: () throws -> ()
    
    init(
        name: String,
        task: @escaping () throws -> ()
    ) {
        self.name = name
        self.task = task
    }
    
    public static func task(_ name: String, task: @escaping () throws -> ()) -> Task {
        Task(
            name: name,
            task: task
        )
    }
    
    private enum CodingKeys: String, CodingKey {
        case name
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        // Decoding loses information about the task's function
        // This is fine as we should never invoke `task` directly but using `swiftc` command instead
        task = { }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
    }
}
