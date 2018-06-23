import Foundation

/// xpm is a thin binary that should be included in the projects, and is responsible
/// for running your commands using the version of the project is pinned to.
///
/// Thanks to xpmrun, developers and continuous integration pipelines don't rely on
/// the environment having the right version of xpm installed via Homebrew.
/// Moreover, it makes building old versions of your project possible, because it'll use
/// the version of xpm the project was built with.
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
