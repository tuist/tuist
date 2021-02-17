import Foundation

public struct Path: ExpressibleByStringInterpolation, Codable, Equatable {
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

    init(_ pathString: String,
         type: PathType,
         callerPath: String? = nil)
    {
        self.type = type
        self.pathString = pathString
        self.callerPath = callerPath
    }

    public static func relativeToCurrentFile(_ pathString: String, callerPath: StaticString = #file) -> Path {
        Path(pathString, type: .relativeToCurrentFile, callerPath: "\(callerPath)")
    }

    public static func relativeToManifest(_ pathString: String) -> Path {
        Path(pathString, type: .relativeToManifest)
    }

    public static func relativeToRoot(_ pathString: String) -> Path {
        Path(pathString, type: .relativeToRoot)
    }

    // MARK: - ExpressibleByStringInterpolation

    public init(stringLiteral: String) {
        if stringLiteral.starts(with: "//") {
            self.init(stringLiteral.replacingOccurrences(of: "//", with: ""), type: .relativeToRoot)
        } else {
            self.init(stringLiteral, type: .relativeToManifest)
        }
    }
}
