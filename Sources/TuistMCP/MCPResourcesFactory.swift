import MCP
import TuistSupport
import ServiceContextModule
import FileSystem

protocol MCPResourcesFactorying {
    func list() async throws -> ListResources.Result
}


struct MCPResourcesFactory: MCPResourcesFactorying {
    let fileSystem: FileSysteming
    
    init() {
        self.init(fileSystem: FileSystem())
    }
    
    init(fileSystem: FileSysteming) {
        self.fileSystem = fileSystem
    }
    
    func list() async throws -> ListResources.Result {
        let resources = try await (ServiceContext.current?.recentPaths?.read() ?? [:])
            .keys
            .concurrentCompactMap({
                (try await fileSystem.exists($0)) ? $0 : nil
            })
            .concurrentMap({
                Resource(name: "\($0.basename) graph",
                         uri: "tuist://\($0.pathString)",
                         description: "A graph representing the project \($0.basename)",
                         mimeType: "application/json")
            })
        
    
        return ListResources.Result(resources: resources)
    }
}
