public struct Template: Codable {
    public let description: String
    
    public init(description: String) {
        self.description = description
        dumpIfNeeded(self)
    }
}
