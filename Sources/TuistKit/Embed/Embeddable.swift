import Basic
import Foundation
import TuistCore

// MARK: - Type

enum EmbeddableType: String {
    case framework = "FMWK"
    case bundle = "BNDL"
    case dSYM
}

enum EmbeddableError: FatalError, Equatable {
    case missingBundleExecutable(AbsolutePath)
    case unstrippableNonFatEmbeddable(AbsolutePath)

    var type: ErrorType {
        switch self {
        case .missingBundleExecutable: return .abort
        case .unstrippableNonFatEmbeddable: return .abort
        }
    }

    var description: String {
        switch self {
        case let .missingBundleExecutable(path):
            return "Couldn't find executable in bundle at path \(path.asString)"
        case let .unstrippableNonFatEmbeddable(path):
            return "Can't strip architectures from the non-fat package at path \(path.asString)"
        }
    }

    static func == (lhs: EmbeddableError, rhs: EmbeddableError) -> Bool {
        switch (lhs, rhs) {
        case let (.missingBundleExecutable(lhsPath), .missingBundleExecutable(rhsPath)):
            return lhsPath == rhsPath
        case let (.unstrippableNonFatEmbeddable(lhsPath), .unstrippableNonFatEmbeddable(rhsPath)):
            return lhsPath == rhsPath
        default:
            return false
        }
    }
}

final class Embeddable {
    enum Constants {
        static let lipoArchitecturesMessage: String = "Architectures in the fat file:"
        static let lipoNonFatFileMessage: String = "Non-fat file:"
    }

    // MARK: - Attributes

    let path: AbsolutePath

    // MARK: - Init

    init(path: AbsolutePath) {
        self.path = path
    }

    // MARK: - Package Information

    func binaryPath() throws -> AbsolutePath? {
        guard let bundle = Bundle(path: path.asString) else { return nil }
        guard let packageType = packageType() else { return nil }
        switch packageType {
        case .framework, .bundle:
            guard let bundleExecutable = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String else {
                throw EmbeddableError.missingBundleExecutable(path)
            }
            return path.appending(RelativePath(bundleExecutable))
        case .dSYM:
            let binaryName = URL(fileURLWithPath: path.asString)
                .deletingPathExtension()
                .deletingPathExtension()
                .lastPathComponent
            if !binaryName.isEmpty {
                return path.appending(RelativePath("Contents/Resources/DWARF/\(binaryName)"))
            }
        }
        return nil
    }

    func packageType() -> EmbeddableType? {
        guard let bundle = Bundle(path: path.asString) else { return nil }
        guard let bundlePackageType = bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String else {
            return nil
        }
        return EmbeddableType(rawValue: bundlePackageType)
    }

    func architectures(system: Systeming = System()) throws -> [String] {
        guard let binPath = try binaryPath() else { return [] }
        let lipoResult = try system.capture("/usr/bin/lipo",
                                            arguments: "-info",
                                            binPath.asString,
                                            verbose: false,
                                            workingDirectoryPath: nil,
                                            environment: nil).stdout.chuzzle() ?? ""
        var characterSet = CharacterSet.alphanumerics
        characterSet.insert(charactersIn: " _-")
        let scanner = Scanner(string: lipoResult)

        if scanner.scanString(Constants.lipoArchitecturesMessage, into: nil) {
            // The output of "lipo -info PathToBinary" for fat files
            // looks roughly like so:
            //
            //     Architectures in the fat file: PathToBinary are: armv7 arm64
            //
            var architectures: NSString?
            scanner.scanString(binPath.asString, into: nil)
            scanner.scanString("are:", into: nil)
            scanner.scanCharacters(from: characterSet, into: &architectures)
            let components = architectures?
                .components(separatedBy: " ")
                .filter { !$0.isEmpty }
            if let components = components {
                return components
            }
        }
        if scanner.scanString(Constants.lipoNonFatFileMessage, into: nil) {
            // The output of "lipo -info PathToBinary" for thin
            // files looks roughly like so:
            //
            //     Non-fat file: PathToBinary is architecture: x86_64
            //
            var architecture: NSString?
            scanner.scanString(binPath.asString, into: nil)
            scanner.scanString("is architecture:", into: nil)
            scanner.scanCharacters(from: characterSet, into: &architecture)
            if let architecture = architecture {
                return [architecture as String]
            }
        }
        return []
    }

    // MARK: - Strip

    func strip(keepingArchitectures: [String]) throws {
        if try architectures().count == 1 {
            throw EmbeddableError.unstrippableNonFatEmbeddable(path)
        }
        switch packageType() {
        case .framework?, .bundle?:
            try stripFramework(keepingArchitectures: keepingArchitectures)
        case .dSYM?:
            try stripDSYM(keepingArchitectures: keepingArchitectures)
        default:
            return
        }
    }

    fileprivate func stripFramework(keepingArchitectures: [String]) throws {
        try stripArchitectures(keepingArchitectures: keepingArchitectures)
        try stripHeaders(frameworkPath: path)
        try stripPrivateHeaders(frameworkPath: path)
        try stripModulesDirectory(frameworkPath: path)
    }

    fileprivate func stripDSYM(keepingArchitectures: [String]) throws {
        try stripArchitectures(keepingArchitectures: keepingArchitectures)
    }

    fileprivate func stripArchitectures(keepingArchitectures: [String]) throws {
        let architecturesInPackage = try architectures()
        let architecturesToStrip = architecturesInPackage.filter({ !keepingArchitectures.contains($0) })
        try architecturesToStrip.forEach({
            if let binaryPath = try binaryPath() {
                try stripArchitecture(packagePath: binaryPath, architecture: $0)
            }
        })
    }

    fileprivate func stripArchitecture(packagePath: AbsolutePath,
                                       architecture: String,
                                       system: Systeming = System()) throws {
        try system.popen("/usr/bin/lipo",
                         arguments: "-remove", architecture, "-output", packagePath.asString, packagePath.asString,
                         verbose: false,
                         workingDirectoryPath: nil,
                         environment: nil)
    }

    fileprivate func stripHeaders(frameworkPath: AbsolutePath) throws {
        try stripDirectory(name: "Headers", from: frameworkPath)
    }

    fileprivate func stripPrivateHeaders(frameworkPath: AbsolutePath) throws {
        try stripDirectory(name: "PrivateHeaders", from: frameworkPath)
    }

    fileprivate func stripModulesDirectory(frameworkPath: AbsolutePath) throws {
        try stripDirectory(name: "Modules", from: frameworkPath)
    }

    fileprivate func stripDirectory(name: String, from frameworkPath: AbsolutePath) throws {
        let fileHandler = FileHandler()
        let path = frameworkPath.appending(RelativePath(name))
        if fileHandler.exists(path) {
            try fileHandler.delete(path)
        }
    }

    // MARK: - UUID

    func uuids() throws -> Set<UUID> {
        switch packageType() {
        case .framework?, .bundle?:
            return try uuidsForFramework()
        case .dSYM?:
            return try uuidsForDSYM()
        default:
            return Set()
        }
    }

    fileprivate func uuidsForFramework() throws -> Set<UUID> {
        guard let binaryPath = try binaryPath() else { return Set() }
        return try uuidsFromDwarfdump(path: binaryPath)
    }

    fileprivate func uuidsForDSYM() throws -> Set<UUID> {
        return try uuidsFromDwarfdump(path: path)
    }

    fileprivate func uuidsFromDwarfdump(path: AbsolutePath,
                                        system: Systeming = System()) throws -> Set<UUID> {
        let result = try system.capture("/usr/bin/dwarfdump",
                                        arguments: "--uuid", path.asString,
                                        verbose: false,
                                        workingDirectoryPath: nil,
                                        environment: nil).stdout.chuzzle() ?? ""
        var uuidCharacterSet = CharacterSet()
        uuidCharacterSet.formUnion(.letters)
        uuidCharacterSet.formUnion(.decimalDigits)
        uuidCharacterSet.formUnion(CharacterSet(charactersIn: "-"))
        let scanner = Scanner(string: result)
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

    func bcSymbolMapsForFramework() throws -> [AbsolutePath] {
        let frameworkUUIDs = try uuids()
        return frameworkUUIDs.map({ path.parentDirectory.appending(RelativePath("\($0.uuidString).bcsymbolmap")) })
    }
}
