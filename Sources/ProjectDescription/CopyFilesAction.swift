import Foundation

/// Copy files actions, represented as target copy files build phases, are useful to associate project files
/// and products of other targets with the target and copies them to a specified destination, typically a
/// subfolder within a product. This action may be used multiple times per target.
public struct CopyFilesAction: Codable, Equatable {
    /// Name of the build phase when the project gets generated.
    public var name: String

    /// Destination to copy files to.
    public var destination: Destination

    /// Path to a folder inside the destination.
    public var subpath: String?

    /// Relative paths to the files to be copied.
    public var files: [FileElement]

    /// Destination path.
    public enum Destination: String, Codable, Equatable {
        case absolutePath
        case productsDirectory
        case wrapper
        case executables
        case resources
        case javaResources
        case frameworks
        case sharedFrameworks
        case sharedSupport
        case plugins
        case other
    }

    init(
        name: String,
        destination: Destination,
        subpath: String? = nil,
        files: [FileElement]
    ) {
        self.name = name
        self.destination = destination
        self.subpath = subpath
        self.files = files
    }

    // MARK: - Static initializers

    /// A copy files action for the products directory.
    /// - Parameters:
    ///   - name: Name of the build phase when the project gets generated.
    ///   - subpath: Path to a folder inside the destination.
    ///   - files: Relative paths to the files to be copied.
    /// - Returns: Copy files action.
    public static func productsDirectory(
        name: String,
        subpath: String? = nil,
        files: [FileElement]
    ) -> CopyFilesAction {
        CopyFilesAction(
            name: name,
            destination: .productsDirectory,
            subpath: subpath,
            files: files
        )
    }

    /// A copy files action for the wrapper directory.
    /// - Parameters:
    ///   - name: Name of the build phase when the project gets generated.
    ///   - subpath: Path to a folder inside the destination.
    ///   - files: Relative paths to the files to be copied.
    /// - Returns: Copy files action.
    public static func wrapper(
        name: String,
        subpath: String? = nil,
        files: [FileElement]
    ) -> CopyFilesAction {
        CopyFilesAction(
            name: name,
            destination: .wrapper,
            subpath: subpath,
            files: files
        )
    }

    /// A copy files action for the executables directory.
    /// - Parameters:
    ///   - name: Name of the build phase when the project gets generated.
    ///   - subpath: Path to a folder inside the destination.
    ///   - files: Relative paths to the files to be copied.
    /// - Returns: Copy files action.
    public static func executables(
        name: String,
        subpath: String? = nil,
        files: [FileElement]
    ) -> CopyFilesAction {
        CopyFilesAction(
            name: name,
            destination: .executables,
            subpath: subpath,
            files: files
        )
    }

    /// A copy files action for the resources directory.
    /// - Parameters:
    ///   - name: Name of the build phase when the project gets generated.
    ///   - subpath: Path to a folder inside the destination.
    ///   - files: Relative paths to the files to be copied.
    /// - Returns: Copy files action.
    public static func resources(
        name: String,
        subpath: String? = nil,
        files: [FileElement]
    ) -> CopyFilesAction {
        CopyFilesAction(
            name: name,
            destination: .resources,
            subpath: subpath,
            files: files
        )
    }

    /// A copy files action for the java resources directory.
    /// - Parameters:
    ///   - name: Name of the build phase when the project gets generated.
    ///   - subpath: Path to a folder inside the destination.
    ///   - files: Relative paths to the files to be copied.
    /// - Returns: Copy files action.
    public static func javaResources(
        name: String,
        subpath: String? = nil,
        files: [FileElement]
    ) -> CopyFilesAction {
        CopyFilesAction(
            name: name,
            destination: .javaResources,
            subpath: subpath,
            files: files
        )
    }

    /// A copy files action for the frameworks directory.
    /// - Parameters:
    ///   - name: Name of the build phase when the project gets generated.
    ///   - subpath: Path to a folder inside the destination.
    ///   - files: Relative paths to the files to be copied.
    /// - Returns: Copy files action.
    public static func frameworks(
        name: String,
        subpath: String? = nil,
        files: [FileElement]
    ) -> CopyFilesAction {
        CopyFilesAction(
            name: name,
            destination: .frameworks,
            subpath: subpath,
            files: files
        )
    }

    /// A copy files action for the shared frameworks directory.
    /// - Parameters:
    ///   - name: Name of the build phase when the project gets generated.
    ///   - subpath: Path to a folder inside the destination.
    ///   - files: Relative paths to the files to be copied.
    /// - Returns: Copy files action.
    public static func sharedFrameworks(
        name: String,
        subpath: String? = nil,
        files: [FileElement]
    ) -> CopyFilesAction {
        CopyFilesAction(
            name: name,
            destination: .sharedFrameworks,
            subpath: subpath,
            files: files
        )
    }

    /// A copy files action for the shared support directory.
    /// - Parameters:
    ///   - name: Name of the build phase when the project gets generated.
    ///   - subpath: Path to a folder inside the destination.
    ///   - files: Relative paths to the files to be copied.
    /// - Returns: Copy files action.
    public static func sharedSupport(
        name: String,
        subpath: String? = nil,
        files: [FileElement]
    ) -> CopyFilesAction {
        CopyFilesAction(
            name: name,
            destination: .sharedSupport,
            subpath: subpath,
            files: files
        )
    }

    /// A copy files action for the plugins directory.
    /// - Parameters:
    ///   - name: Name of the build phase when the project gets generated.
    ///   - subpath: Path to a folder inside the destination.
    ///   - files: Relative paths to the files to be copied.
    /// - Returns: Copy files action.
    public static func plugins(
        name: String,
        subpath: String? = nil,
        files: [FileElement]
    ) -> CopyFilesAction {
        CopyFilesAction(
            name: name,
            destination: .plugins,
            subpath: subpath,
            files: files
        )
    }
}
