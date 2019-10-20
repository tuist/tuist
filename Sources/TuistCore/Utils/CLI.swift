import Basic

public struct CLI: Equatable, Codable {
    
    public var path: AbsolutePath
    public var projectOnly: Bool
    public var carthage: Carthage
    public var verbose: Bool
    
    public struct Carthage: Equatable, Codable {
        public var projects: Bool
        public var SSH: Bool
        public var submodules: Bool
        public var projectDirectory: AbsolutePath?
    }

    public static var arguments: CLI = .init(
        path: FileHandler.shared.currentPath,
        projectOnly: false,
        carthage: .init(
            projects: false,
            SSH: true,
            submodules: false,
            projectDirectory: nil
        ),
        verbose: false
    )
    
}
