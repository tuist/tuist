import Foundation

/// The structure defining the output schema of a Xcode project.
public struct ProjectOutput: Codable, Equatable {
    
    /// The name of the project.
    public let name: String
    
    /// The absolute path of the project.
    public let path: String
    
    /// The Swift packages that this project depends on.
    public let packages: [PackageOutput]
    
    /// The targets this project produces.
    public let targets: [TargetOutput]
    
    /// The schemes available to this project.
    public let schemes: [SchemeOutput]
    
    public init(
        name: String,
        path: String,
        packages: [PackageOutput] = [PackageOutput](),
        targets: [TargetOutput] = [TargetOutput](),
        schemes: [SchemeOutput] = [SchemeOutput]()) {
        self.name = name
        self.path = path
        self.packages = packages
        self.targets = targets
        self.schemes = schemes
    }
    
    /// Factory function to convert an internal graph project to the output type.
    public static func from(_ project: Project) -> ProjectOutput {
        let packages = project.packages.reduce(into: [PackageOutput](), {$0.append(PackageOutput.from($1))})
        let schemes = project.schemes.reduce(into: [SchemeOutput](), {$0.append(SchemeOutput.from($1))})
        let targets = project.targets.reduce(into: [TargetOutput](), {$0.append(TargetOutput.from($1))})
        
        return ProjectOutput(name: project.name, path: project.path.pathString, packages: packages, targets: targets, schemes: schemes)
    }
}
