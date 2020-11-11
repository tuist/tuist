import ProjectDescription
import LocalTuistHelpers // Test that we can import plugins from default helpers

public extension Project {
    static func iOSApp(name: String) -> Self {
        Project.app(name: name, platform: .iOS)
    }    
}
