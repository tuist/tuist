import Foundation

/// xpm is a thin binary that should be included in the projects, and is responsible
/// for running your commands using the version of the project is pinned to. By using it:
///
/// - Projects don't need to include the xpm tool in the repository.
/// - They run the version of xpm the project is pinned to, ensuring reproducibility.
/// - Abstract developers from having to setup the environment properly to work with the project.
///
/// The version of xpm is specified using a .xpm-version file in your project's directory.
/// If your project has subfolders, xpmrun will lookup the version file in the ancestors.
let fileManager = FileManager.default
let session = URLSession.shared

// Version
func lookupVersion(path: URL) throws -> String? {
    let xpmVersionURL = currentDirectory.appendingPathComponent(".xpm-version")
    if fileManager.fileExists(atPath: xpmVersionURL.path) {
        return try String(contentsOf: xpmVersionURL)
    } else if path.pathComponents.count > 1 {
        return try lookupVersion(path: path.deletingLastPathComponent())
    } else {
        return nil
    }
}
let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let version = try lookupVersion(path: currentDirectory)


// TODO
// - If xpm-version is defined
//      - Run it if it exists locally
//      - Download it and run it if it doesn't exist.
// - If xpm-version is not defined
//      - Get the laste version available locally.
//      - Compare it with the latest remote version.
//      - If there's a new remote version download it and run it using that one.
