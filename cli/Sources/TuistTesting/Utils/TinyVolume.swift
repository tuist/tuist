import Foundation
import Path

/// A real 2 MB APFS volume. Writes into it fail with the same ENOSPC the runner cache image
/// raises, rather than a hand-made error that would only prove a matcher matches its own fixture.
///
/// It mounts outside the test's temporary directory: a full volume inside the tree the test host
/// writes its own output into makes the host fail those writes.
public struct TinyVolume {
    public let mountPoint: AbsolutePath
    private let baseDirectory: AbsolutePath

    public static func attached() throws -> TinyVolume {
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

    /// Consumes the volume's remaining free space so the next write raises ENOSPC.
    ///
    /// Appends in chunks rather than handing the whole payload to `FileManager.createFile`, which
    /// deletes its partial file when the volume fills and so leaves the volume as empty as it found it.
    ///
    /// APFS hands back space after a writer gives up, so one pass leaves room for the small write
    /// this is meant to starve. Each pass therefore opens a fresh file and halves the chunk, down to
    /// a size below anything the code under test would write.
    public func fill() {
        var chunkSize = 64 * 1024
        var pass = 0
        while chunkSize >= 512 {
            let filler = mountPoint.appending(component: "filler.\(pass)").pathString
            FileManager.default.createFile(atPath: filler, contents: nil)
            if let handle = FileHandle(forWritingAtPath: filler) {
                let chunk = Data(repeating: 0x41, count: chunkSize)
                while (try? handle.write(contentsOf: chunk)) != nil {}
                try? handle.close()
            }
            chunkSize /= 2
            pass += 1
        }
    }

    public func detach() {
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
