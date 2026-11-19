import Foundation
import Path

/// The entry point, relative to the root of an executable preview archive.
public struct ExecutablePreviewManifest: Codable {
    public static let filename = "tuist-preview.json"

    public let executable: RelativePath

    public init(executable: RelativePath) {
        self.executable = executable
    }
}

public struct ExecutablePreviewTarget: Equatable {
    public let platform: String
    public let architectures: [String]

    public static var host: Self {
        #if os(macOS)
            let platform = "macos"
        #else
            let platform = "linux"
        #endif
        #if arch(arm64)
            let architecture = "arm64"
        #else
            let architecture = "x86_64"
        #endif
        return Self(platform: platform, architectures: [architecture])
    }

    public var isCompatible: Bool {
        platform == Self.host.platform && (architectures.isEmpty || architectures.contains(Self.host.architectures[0]))
    }

    public init(platform: String, architectures: [String]) {
        self.platform = platform
        self.architectures = architectures
    }

    /// Reads the target from Mach-O/ELF headers without executing publisher code.
    /// Scripts require the publisher's OS and an interpreter supplied by the recipient.
    public static func read(at url: URL) throws -> Self {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = [UInt8](try handle.read(upToCount: 4096) ?? Data())
        func word(_ offset: Int, littleEndian: Bool = true) -> UInt32? {
            guard offset >= 0, offset + 4 <= bytes.count else { return nil }
            let value = bytes[offset ..< (offset + 4)]
            return (littleEndian ? Array(value.reversed()) : Array(value)).reduce(0) { ($0 << 8) | UInt32($1) }
        }
        func architecture(_ cpu: UInt32?) -> String? {
            switch cpu {
            case 0x0100_000C: return "arm64"
            case 0x0100_0007: return "x86_64"
            default: return nil
            }
        }
        if bytes.starts(with: [0x23, 0x21]) {
            return Self(platform: host.platform, architectures: [])
        }
        if bytes.starts(with: [0x7F, 0x45, 0x4C, 0x46]), bytes.count >= 64, bytes[4] == 2, bytes[5] == 1 {
            let machine = UInt16(bytes[18]) | UInt16(bytes[19]) << 8
            if let arch = [UInt16(62): "x86_64", UInt16(183): "arm64"][machine] {
                return Self(platform: "linux", architectures: [arch])
            }
        }
        if word(0) == 0xFEED_FACF, let arch = architecture(word(4)), word(12) == 2 {
            return Self(platform: "macos", architectures: [arch])
        }
        if word(0, littleEndian: false) == 0xCAFE_BABE,
           let count = word(4, littleEndian: false), count > 0, count <= 16,
           8 + Int(count) * 20 <= bytes.count
        {
            let architectures = (0 ..< Int(count)).compactMap { architecture(word(8 + $0 * 20, littleEndian: false)) }
            if !architectures.isEmpty {
                return Self(platform: "macos", architectures: Array(Set(architectures)).sorted())
            }
        }
        throw UnsupportedExecutable()
    }
}

private struct UnsupportedExecutable: LocalizedError {
    var errorDescription: String? {
        "Expected a 64-bit macOS Mach-O, Linux ELF executable, or a script with a shebang. Package a distribution with a supported entry point."
    }
}
