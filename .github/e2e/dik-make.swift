import DiskImageKit
import Foundation
// dik-make <base> <layer or ""> <new overlay>
let a = CommandLine.arguments
var parent = try DiskImage(opening: .open(url: URL(fileURLWithPath: a[1]), mode: .readOnly))
if !a[2].isEmpty { parent = try parent.appending(try DiskImage(opening: .open(url: URL(fileURLWithPath: a[2]), mode: .readOnly))) }
_ = try parent.appending(.asifLayer(url: URL(fileURLWithPath: a[3]), type: .overlay))
print("created \(a[3])")
