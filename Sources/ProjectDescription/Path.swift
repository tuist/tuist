public struct Path: Codable, ExpressibleByStringLiteral, Equatable {
    
    public enum PathType: String, Codable {
        case relativeToCurrentFile
        case relativeToManifest
    }
    
    public let type: PathType
    public let path: String
    public let callerPath: String?
    
    public init(_ path: String) {
        self.init(path, type: .relativeToManifest)
    }
    
    private init(_ path: String,
                 type: PathType,
                 callerPath: String? = nil) {
        self.type = type
        self.path = path
        self.callerPath = callerPath
    }
    
    public static func relativeToCurrentFile(_ path: String, callerPath: StaticString = #file) -> Path {
        return Path(path, type: .relativeToCurrentFile, callerPath: "\(callerPath)")
    }
    
    public static func relativeToManifest(_ path: String) -> Path {
        return Path(path, type: .relativeToManifest)
    }
    
    // MARK: - ExpressibleByStringLiteral
        
    public init(stringLiteral: String) {
        self.init(stringLiteral, type: .relativeToManifest)
    }
}
