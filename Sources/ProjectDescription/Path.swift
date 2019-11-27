public struct Path: Codable, ExpressibleByStringLiteral, Equatable {
    public enum PathType: String, Codable {
        case relativeToCurrentFile
        case relativeToManifest
        case relativeToRoot
    }

    public let type: PathType
    public let pathString: String
    public let callerPath: String?

    public init(_ path: String) {
        self.init(path, type: .relativeToManifest)
    }

    private init(_ pathString: String,
                 type: PathType,
                 callerPath: String? = nil) {
        self.type = type
        self.pathString = pathString
        self.callerPath = callerPath
    }

    public static func relativeToCurrentFile(_ pathString: String, callerPath: StaticString = #file) -> Path {
        return Path(pathString, type: .relativeToCurrentFile, callerPath: "\(callerPath)")
    }

    public static func relativeToManifest(_ pathString: String) -> Path {
        return Path(pathString, type: .relativeToManifest)
    }

    public static func relativeToRoot(_ pathString: String) -> Path {
        return Path(pathString, type: .relativeToRoot)
    }

    // MARK: - ExpressibleByStringLiteral

    public init(stringLiteral: String) {
        self.init(stringLiteral, type: .relativeToManifest)
    }
}
