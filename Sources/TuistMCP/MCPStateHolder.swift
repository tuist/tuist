import Path
import TuistSupport

/// Since the MCP server is local to the developer, we can leverage in-memory state
/// to improve the experience. For example by allowing developers to select the active
/// project.
class MCPStateHolder {
    /// Active project.
    let activeProject: ThreadSafe<AbsolutePath?> = ThreadSafe(nil)
}
