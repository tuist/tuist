public struct CLIOptions {
    
    public let projectOnly: Bool
    public let carthageProjects: Bool
    public let verbose: Bool
    
    public init(projectOnly: Bool, carthageProjects: Bool, verbose: Bool) {
        self.projectOnly = projectOnly
        self.carthageProjects = carthageProjects
        self.verbose = verbose
    }
    
    public static var current: CLIOptions = CLIOptions(
        projectOnly: false,
        carthageProjects: false,
        verbose: false
    )
    
}
