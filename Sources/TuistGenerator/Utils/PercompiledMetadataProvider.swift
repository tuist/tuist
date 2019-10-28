import Basic
import Foundation
import TuistCore

enum BinaryArchitecture: String {
    case x8664 = "x86_64"
    case i386
    case armv7
    case armv7s
    case arm64
}

enum BinaryLinking: String {
    case `static`, dynamic
}

enum PrecompiledMetadataProviderError: FatalError, Equatable {
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

    static func == (lhs: PrecompiledMetadataProviderError, rhs: PrecompiledMetadataProviderError) -> Bool {
        switch (lhs, rhs) {
        case let (.architecturesNotFound(lhsPath), .architecturesNotFound(rhsPath)):
            return lhsPath == rhsPath
        }
    }
}

protocol PrecompiledMetadataProviding {
    /// It returns the supported architectures of the binary at the given path.
    /// - Parameter binaryPath: Binary path.
    func architectures(binaryPath: AbsolutePath) throws -> [BinaryArchitecture]

    /// It returns the supported architectures of the precompiled framework or library.
    /// - Parameter precompiled: Precompiled framework or library.
    func architectures(precompiled: PrecompiledNode) throws -> [BinaryArchitecture]

    /// Return how other binaries should link the binary at the given path.
    /// - Parameter binaryPath: Path to the binary.
    func linking(binaryPath: AbsolutePath) throws -> BinaryLinking

    /// Return how other binaries should link the given precompiled framework or library.
    /// - Parameter precompiled: Precompiled framework or library.
    func linking(precompiled: PrecompiledNode) throws -> BinaryLinking

    /// It uses 'dwarfdump' to dump the UUIDs of each architecture.
    /// The UUIDs allows us to know which .bcsymbolmap files belong to this binary.
    /// - Parameter binaryPath: Path to the binary.
    func uuids(binaryPath: AbsolutePath) throws -> Set<UUID>

    /// It uses 'dwarfdump' to dump the UUIDs of each architecture.
    /// The UUIDs allows us to know which .bcsymbolmap files belong to this binary.
    /// - Parameter precompiled: Precompiled framework or library.
    func uuids(precompiled: PrecompiledNode) throws -> Set<UUID>
}

class PrecompiledMetadataProvider: PrecompiledMetadataProviding {
    func architectures(precompiled: PrecompiledNode) throws -> [BinaryArchitecture] {
        return try architectures(binaryPath: precompiled.binaryPath)
    }

    func architectures(binaryPath: AbsolutePath) throws -> [BinaryArchitecture] {
        let result = try System.shared.capture("/usr/bin/lipo", "-info", binaryPath.pathString).spm_chuzzle() ?? ""
        let regexes = [
            // Non-fat file: path is architecture: x86_64
            try NSRegularExpression(pattern: ".+:\\s.+\\sis\\sarchitecture:\\s(.+)", options: []),
            // Architectures in the fat file: /path/xpm.framework/xpm are: x86_64 arm64
            try NSRegularExpression(pattern: "Architectures\\sin\\sthe\\sfat\\sfile:.+:\\s(.+)", options: []),
        ]

        guard let architectures = regexes.compactMap({ (regex) -> [BinaryArchitecture]? in
            guard let match = regex.firstMatch(in: result, options: [], range: NSRange(location: 0, length: result.count)) else {
                return nil
            }
            let architecturesString = (result as NSString).substring(with: match.range(at: 1))
            return architecturesString.split(separator: " ").map(String.init).compactMap(BinaryArchitecture.init)
        }).first else {
            throw PrecompiledMetadataProviderError.architecturesNotFound(binaryPath)
        }
        return architectures
    }

    func linking(precompiled: PrecompiledNode) throws -> BinaryLinking {
        return try linking(binaryPath: precompiled.binaryPath)
    }

    func linking(binaryPath: AbsolutePath) throws -> BinaryLinking {
        let result = try System.shared.capture("/usr/bin/file", binaryPath.pathString).spm_chuzzle() ?? ""
        return result.contains("dynamically linked") ? .dynamic : .static
    }

    func uuids(precompiled: PrecompiledNode) throws -> Set<UUID> {
        return try uuids(binaryPath: precompiled.binaryPath)
    }

    func uuids(binaryPath: AbsolutePath) throws -> Set<UUID> {
        let output = try System.shared.capture(["/usr/bin/xcrun", "dwarfdump", "--uuid", binaryPath.pathString])
        // UUIDs are letters, decimals, or hyphens.
        var uuidCharacterSet = CharacterSet()
        uuidCharacterSet.formUnion(.letters)
        uuidCharacterSet.formUnion(.decimalDigits)
        uuidCharacterSet.formUnion(CharacterSet(charactersIn: "-"))

        let scanner = Scanner(string: output)
        var uuids = Set<UUID>()

        // The output of dwarfdump is a series of lines formatted as follows
        // for each architecture:
        //
        //     UUID: <UUID> (<Architecture>) <PathToBinary>
        //
        while !scanner.isAtEnd {
            scanner.scanString("UUID: ", into: nil)

            var uuidString: NSString?
            scanner.scanCharacters(from: uuidCharacterSet, into: &uuidString)

            if let uuidString = uuidString as String?, let uuid = UUID(uuidString: uuidString) {
                uuids.insert(uuid)
            }

            // Scan until a newline or end of file.
            scanner.scanUpToCharacters(from: .newlines, into: nil)
        }
        return uuids
    }
}
