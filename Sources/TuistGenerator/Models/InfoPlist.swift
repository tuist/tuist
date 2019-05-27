import Basic
import Foundation
import TuistCore

public enum InfoPlist: Equatable, ExpressibleByStringLiteral, ExpressibleByUnicodeScalarLiteral, ExpressibleByExtendedGraphemeClusterLiteral {
    case file(path: AbsolutePath)

    public static func == (lhs: InfoPlist, rhs: InfoPlist) -> Bool {
        switch (lhs, rhs) {
        case let (.file(lhsPath), .file(rhsPath)):
            return lhsPath == rhsPath
        default:
            return false
        }
    }

    public var path: AbsolutePath {
        switch self {
        case let .file(path):
            return path
        }
    }

    // MARK: - ExpressibleByStringLiteral

    public typealias UnicodeScalarLiteralType = String
    public typealias ExtendedGraphemeClusterLiteralType = String
    public typealias StringLiteralType = String

    public init(stringLiteral value: String) {
        self = .file(path: AbsolutePath(value))
    }
}
