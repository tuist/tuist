import DiskImageKit
import Foundation

// Which layers does a stack hold when a stacked parent is appended to twice,
// as Tart's hot-plug patch does, against a chain opened afresh?
let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dik-probe-\(getpid())")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let base = dir.appendingPathComponent("base.asif")
let create = Process()
create.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
create.arguments = ["image", "create", "blank", "--fs", "APFS", "--format", "ASIF", "--size", "1G", "--volumeName", "Probe", base.path]
try create.run(); create.waitUntilExit()
func describe(_ label: String, _ image: any StackedImage) {
  print("PROBE \(label): " + image.layers.map { "\($0.url.lastPathComponent)(\($0.layerUUID?.uuidString.prefix(8) ?? "-")<-\($0.parentUUID?.uuidString.prefix(8) ?? "-"))" }.joined(separator: " | "))
}
func chain(_ urls: [URL]) throws -> DiskImage {
  var parent = try DiskImage(opening: .open(url: urls[0], mode: .readOnly))
  for url in urls.dropFirst() { parent = try parent.appending(try DiskImage(opening: .open(url: url, mode: .readOnly))) }
  return parent
}
// Round 1: base + overlay1, then overlay1 becomes a layer.
let layer1 = dir.appendingPathComponent("layer1.asif")
_ = try DiskImage(opening: .open(url: base, mode: .readOnly)).appending(.asifLayer(url: layer1, type: .overlay))
// Tart's pattern for round 2.
let overlay2 = dir.appendingPathComponent("overlay2.asif")
let parent = try chain([base, layer1])
describe("parent before", parent as! any StackedImage)
_ = try parent.appending(.asifLayer(url: overlay2, type: .overlay))
describe("parent after creating", parent as! any StackedImage)
let stacked = try parent.appending(try DiskImage(opening: .open(url: overlay2, mode: .readWrite)))
describe("tart pattern", stacked)
// Afresh: create on one chain, attach on a new one.
let overlay3 = dir.appendingPathComponent("overlay3.asif")
_ = try chain([base, layer1]).appending(.asifLayer(url: overlay3, type: .overlay))
describe("fresh chain", try chain([base, layer1]).appending(try DiskImage(opening: .open(url: overlay3, mode: .readWrite))))
describe("created directly", try chain([base, layer1]).appending(.asifLayer(url: dir.appendingPathComponent("overlay4.asif"), type: .overlay)))
