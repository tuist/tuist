import Foundation
import Basic

public protocol Git {
    func isFileBeingTracked(path: AbsolutePath) -> Bool
}

public class GitClient: Git {
    
    internal let directory: AbsolutePath
    internal let system: Systeming
    
    public init(directory: AbsolutePath, system: Systeming = System()) {
        self.directory = directory
        self.system = system
    }
    
    public func isFileBeingTracked(path: AbsolutePath) -> Bool {
        do {
            let capture = try system.capture([ "git", "--git-dir", directory.appending(component: ".git").asString, "ls-files", "--error-unmatch", path.relative(to: directory).asString ])
            return capture.isEmpty == false
        } catch {
            return false
        }
    }
    
}
