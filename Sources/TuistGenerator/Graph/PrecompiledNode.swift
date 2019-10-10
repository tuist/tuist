import Basic
import Foundation
import TuistCore

enum PrecompiledNodeError: FatalError, Equatable {
    case architecturesNotFound(AbsolutePath)

    // MARK: - FatalError

    var description: String {
        switch self {
        case let .architecturesNotFound(path):
            return "Couldn't find architectures for binary at path \(path.pathString)"
        }
    }

    var type: ErrorType {
        switch self {
        case .architecturesNotFound:
            return .abort
        }
    }

    // MARK: - Equatable

    static func == (lhs: PrecompiledNodeError, rhs: PrecompiledNodeError) -> Bool {
        switch (lhs, rhs) {
        case let (.architecturesNotFound(lhsPath), .architecturesNotFound(rhsPath)):
            return lhsPath == rhsPath
        }
    }
}

class PrecompiledNode: GraphNode {
    enum Linking: String {
        case `static`, dynamic
    }

    enum Architecture: String {
        case x8664 = "x86_64"
        case i386
        case armv7
        case armv7s
        case arm64
    }

    init(path: AbsolutePath) {
        /// Returns the name of the precompiled node removing the extension
        /// Alamofire.framework -> Alamofire
        /// libAlamofire.a -> libAlamofire
        let name = String(path.components.last!.split(separator: ".").first!)
        super.init(path: path, name: name)
    }

    var binaryPath: AbsolutePath {
        fatalError("This method should be overriden by the subclasses")
    }

    func architectures() throws -> [Architecture] {
        let result = try System.shared.capture("/usr/bin/lipo", "-info", binaryPath.pathString).spm_chuzzle() ?? ""
        let regexes = [
            // Non-fat file: path is architecture: x86_64
            try NSRegularExpression(pattern: ".+:\\s.+\\sis\\sarchitecture:\\s(.+)", options: []),
            // Architectures in the fat file: /path/xpm.framework/xpm are: x86_64 arm64
            try NSRegularExpression(pattern: "Architectures\\sin\\sthe\\sfat\\sfile:.+:\\s(.+)", options: []),
        ]

        guard let architectures = regexes.compactMap({ (regex) -> [Architecture]? in
            guard let match = regex.firstMatch(in: result, options: [], range: NSRange(location: 0, length: result.count)) else {
                return nil
            }
            let architecturesString = (result as NSString).substring(with: match.range(at: 1))
            return architecturesString.split(separator: " ").map(String.init).compactMap(Architecture.init)
        }).first else {
            throw PrecompiledNodeError.architecturesNotFound(binaryPath)
        }
        return architectures
    }

    func linking() throws -> Linking {
        let result = try System.shared.capture("/usr/bin/file", binaryPath.pathString).spm_chuzzle() ?? ""
        return result.contains("dynamically linked") ? .dynamic : .static
    }

    enum CodingKeys: String, CodingKey {
        case path
        case name
        case architectures
        case product
        case type
    }
}
