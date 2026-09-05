import Foundation
import Path

/// A real 2 MB APFS volume. Copies into it fail with the same ENOSPC the runner cache image
/// raises, rather than a hand-made error that would only prove a matcher matches its own fixture.
///
/// It mounts outside the test's temporary directory: a full volume inside the tree the test host
/// writes its own output into makes the host fail those writes.
struct TinyVolume {
    let mountPoint: AbsolutePath
    private let baseDirectory: AbsolutePath

    static func attached() throws -> TinyVolume {
        let baseDirectory = try AbsolutePath(
            validating: FileManager.default.temporaryDirectory
                .appendingPathComponent("tuist-tiny-volume-\(UUID().uuidString)").path
        )
        let mountPoint = baseDirectory.appending(component: "mount")
        try FileManager.default.createDirectory(atPath: mountPoint.pathString, withIntermediateDirectories: true)
        let image = baseDirectory.appending(component: "tiny")
        try hdiutil([
            "create", "-size", "2m", "-fs", "APFS", "-volname", "TuistCache", "-type", "SPARSE",
            "-quiet", image.pathString,
        ])
        try hdiutil([
            "attach", image.pathString + ".sparseimage", "-nobrowse", "-noverify", "-quiet",
            "-mountpoint", mountPoint.pathString,
        ])
        return TinyVolume(mountPoint: mountPoint, baseDirectory: baseDirectory)
    }

    func detach() {
        try? Self.hdiutil(["detach", mountPoint.pathString, "-force", "-quiet"])
        try? FileManager.default.removeItem(atPath: baseDirectory.pathString)
    }

    @discardableResult
    private static func hdiutil(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
