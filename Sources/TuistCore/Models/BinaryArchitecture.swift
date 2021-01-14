import Foundation

public enum BinaryArchitecture: String, Codable {
    case x8664 = "x86_64"
    case i386
    case armv7
    case armv7s
    case arm64
    case armv7k
    case arm6432 = "arm64_32"
    case arm64e
}

public enum BinaryLinking: String, Codable {
    case `static`, dynamic
}

public extension Sequence where Element == BinaryArchitecture {
    /// Returns true if all the architectures are only for simulator.
    var onlySimulator: Bool {
        let simulatorArchitectures: [BinaryArchitecture] = [.x8664, .i386]
        return allSatisfy { simulatorArchitectures.contains($0) }
    }
}
