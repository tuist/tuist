import Basic
import Foundation
import xpmcore

// MARK: - Type

/// Embeddable type.
///
/// - framework: the embeddable is a framework.
/// - bundle: the embeddable is a bundle with resoureces.
/// - dSYM: the embeddable contains dynamic symbols.
enum EmbeddableType: String {
    case framework = "FMWK"
    case bundle = "BNDL"
    case dSYM
}

// MARK: - Errors

/// Embeddable errors.
///
/// - missingBundleExecutable: the bundle misses an executable.
/// - unstrippableNonFatEmbeddable: thrown when architectures cannot be stripped from a framework because it's not a fat framework.
enum EmbeddableError: FatalError, Equatable {
    case missingBundleExecutable(AbsolutePath)
    case unstrippableNonFatEmbeddable(AbsolutePath)

    /// Error type
    var type: ErrorType {
        switch self {
        case .missingBundleExecutable: return .abort
        case .unstrippableNonFatEmbeddable: return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .missingBundleExecutable(path):
            return "Couldn't find executable in bundle at path \(path.asString)"
        case let .unstrippableNonFatEmbeddable(path):
            return "Can't strip architectures from the non-fat package at path \(path.asString)"
        }
    }

    /// Returns true if two instances of EmbeddableError are the same.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are the same.
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

/// It represents an element that can be embedded into an Xcode product (e.g. a dynamic framework).
final class Embeddable {
    /// Embeddable constants.
    enum Constants {
        static let lipoArchitecturesMessage: String = "Architectures in the fat file:"
        static let lipoNonFatFileMessage: String = "Non-fat file:"
    }

    /// Embeddable path.
    let path: AbsolutePath

    /// Shell.
    let shell: Shelling

    /// File handler.
    let fileHandler: FileHandling

    /// Initializes the Embeddable with its attributes.
    ///
    /// - Parameters:
    ///   - path: path to the embeddable.
    ///   - shell: shell util.
    ///   - fileHandler: file handler util.
    init(path: AbsolutePath,
         shell: Shelling = Shell(),
         fileHandler: FileHandling = FileHandler()) {
        self.path = path
        self.shell = shell
        self.fileHandler = fileHandler
    }

    // MARK: - Package Information

    /// Returns the path of the binary inside the embeddable.
    /// If the bundle doesn't contain binary it returns nil.
    ///
    /// - Returns: path of the binary (if it exists).
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

    /// Returns the package type.
    ///
    /// - Returns: package type.
    func packageType() -> EmbeddableType? {
        guard let bundle = Bundle(path: path.asString) else { return nil }
        guard let bundlePackageType = bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String else {
            return nil
        }
        return EmbeddableType(rawValue: bundlePackageType)
    }

    /// Returns the supported architectures of the given package.
    ///
    /// - Returns: all the supported architectures.
    func architectures() throws -> [String] {
        let shell = Shell()
        guard let binPath = try binaryPath() else { return [] }
        let lipoResult = try shell.runAndOutput("lipo", "-info", binPath.asString)
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

    /// Strips the package content to contain only the necessary data for the given architectures.
    ///
    /// - Parameter keepingArchitectures: architectures to keep in the package.
    /// - Throws: throws an error if the stripping fails.
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

    /// Strips unnecessary content from a framework.
    ///
    /// - Parameter keepingArchitectures: architectures to be kept.
    /// - Throws: throws an error if the stripping fails.
    fileprivate func stripFramework(keepingArchitectures: [String]) throws {
        try stripArchitectures(keepingArchitectures: keepingArchitectures)
        try stripHeaders(frameworkPath: path)
        try stripPrivateHeaders(frameworkPath: path)
        try stripModulesDirectory(frameworkPath: path)
    }

    /// Strips unnecessary architectures from a DSYM package.
    ///
    /// - Parameter keepingArchitectures: architectures to be kept.
    /// - Throws: throws an error if the stripping fails.
    fileprivate func stripDSYM(keepingArchitectures: [String]) throws {
        try stripArchitectures(keepingArchitectures: keepingArchitectures)
    }

    /// Strips the unnecessary architectures from the package.
    ///
    /// - Parameter keepingArchitectures: architectures to be kept.
    /// - Throws: an error if the stripping fails.
    fileprivate func stripArchitectures(keepingArchitectures: [String]) throws {
        let architecturesInPackage = try architectures()
        let architecturesToStrip = architecturesInPackage.filter({ !keepingArchitectures.contains($0) })
        try architecturesToStrip.forEach({
            if let binaryPath = try binaryPath() {
                try stripArchitecture(packagePath: binaryPath, architecture: $0)
            }
        })
    }

    /// Strips an architecture from a given package.
    ///
    /// - Parameters:
    ///   - packagePath: package path.
    ///   - architecture: architecture to be stripped.
    /// - Throws: throws an error if the stripping fails.
    fileprivate func stripArchitecture(packagePath: AbsolutePath, architecture: String) throws {
        let shell = Shell()
        _ = try shell.run("lipo", "-remove", architecture, "-output", packagePath.asString, packagePath.asString)
    }

    /// Strips the headers from a given framework.
    ///
    /// - Parameter frameworkPath: path to the framework whose headers will be stripped.
    fileprivate func stripHeaders(frameworkPath: AbsolutePath) throws {
        try stripDirectory(name: "Headers", from: frameworkPath)
    }

    /// Strips the private headers from a given framework.
    ///
    /// - Parameter frameworkPath: path to the framework whose private headers will be stripped.
    fileprivate func stripPrivateHeaders(frameworkPath: AbsolutePath) throws {
        try stripDirectory(name: "PrivateHeaders", from: frameworkPath)
    }

    /// Strips the modules directory from a given framework.
    ///
    /// - Parameter frameworkPath: path to the framework whose modules directory will be stripped.
    fileprivate func stripModulesDirectory(frameworkPath: AbsolutePath) throws {
        try stripDirectory(name: "Modules", from: frameworkPath)
    }

    /// Strips a directory from a given framework.
    ///
    /// - Parameters:
    ///   - name: name of the folder that will be stripped from the framework.
    ///   - frameworkPath: path to the framework whose directory will be stripped.
    fileprivate func stripDirectory(name: String, from frameworkPath: AbsolutePath) throws {
        let fileHandler = FileHandler()
        let path = frameworkPath.appending(RelativePath(name))
        if fileHandler.exists(path) {
            try fileHandler.delete(path)
        }
    }

    // MARK: - UUID

    /// Returns a set of UUIDs for each architecture present in the package.
    ///
    /// - Returns: set of UUIDs.
    /// - Throws: an error if the UUIDs cannot be obtained.
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

    /// Returns a set of UUIDs for each architecture present in the framework package.
    ///
    /// - Returns: set of UUIDs.
    /// - Throws: an error if the UUIDs cannot be obtained.
    fileprivate func uuidsForFramework() throws -> Set<UUID> {
        guard let binaryPath = try binaryPath() else { return Set() }
        return try uuidsFromDwarfdump(path: binaryPath)
    }

    /// Returns a set of UUIDs for each architecture present in the DSYM package.
    ///
    /// - Returns: set of UUIDs.
    /// - Throws: an error if the UUIDs cannot be obtained.
    fileprivate func uuidsForDSYM() throws -> Set<UUID> {
        return try uuidsFromDwarfdump(path: path)
    }

    /// Returns a set of UUIDs for each architecture present.
    ///
    /// - Parameter path: url of the file whose architectures UUIDs will be returned.
    /// - Returns: set of UUIDs.
    /// - Throws: an error if the UUIDs cannot be obtained.
    fileprivate func uuidsFromDwarfdump(path: AbsolutePath) throws -> Set<UUID> {
        let shell = Shell()
        let result = try shell.runAndOutput("dwarfdump", "--uuid", path.asString)
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

    /// Returns framework bcsymbolmaps paths.
    ///
    /// - Returns: bcsymbolmaps paths.
    /// - Throws: an error if the bcsymbolmaps cannot be obtained.
    public func bcSymbolMapsForFramework() throws -> [AbsolutePath] {
        let frameworkUUIDs = try uuids()
        return frameworkUUIDs.map({ path.parentDirectory.appending(RelativePath("\($0.uuidString).bcsymbolmap")) })
    }
}
