import DiskImageKit
import Foundation

// Does DiskImageKit refuse a second read-write open of an image another
// DiskImage holds, and allow it once that one is released?
let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dik-probe-\(getpid())")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let base = dir.appendingPathComponent("base.asif"), overlay = dir.appendingPathComponent("overlay.asif")
let create = Process()
create.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
create.arguments = ["image", "create", "blank", "--fs", "APFS", "--format", "ASIF", "--size", "1G", "--volumeName", "Probe", base.path]
try create.run(); create.waitUntilExit()
let parent = try DiskImage(opening: .open(url: base, mode: .readOnly))
_ = try parent.appending(.asifLayer(url: overlay, type: .overlay))
var held: DiskImage? = try DiskImage(opening: .open(url: overlay, mode: .readWrite))
do { _ = try DiskImage(opening: .open(url: overlay, mode: .readWrite)); print("PROBE second read-write open while held: allowed") }
catch { print("PROBE second read-write open while held: refused: \(error)") }
do { _ = try DiskImage(opening: .open(url: overlay, mode: .readOnly)); print("PROBE read-only open while held: allowed") }
catch { print("PROBE read-only open while held: refused: \(error)") }
held = nil
do { _ = try DiskImage(opening: .open(url: overlay, mode: .readWrite)); print("PROBE read-write open after release: allowed") }
catch { print("PROBE read-write open after release: refused: \(error)") }
// flock: does DiskImageKit hold an advisory lock on the file?
let other = try DiskImage(opening: .open(url: overlay, mode: .readWrite))
let fd = open(overlay.path, O_RDONLY)
print("PROBE flock(LOCK_EX|LOCK_NB) while held:", flock(fd, LOCK_EX | LOCK_NB) == 0 ? "acquired" : "refused errno \(errno)")
_ = other
