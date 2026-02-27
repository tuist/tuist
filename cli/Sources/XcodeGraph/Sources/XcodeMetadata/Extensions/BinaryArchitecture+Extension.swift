import Foundation
#if canImport(MachO)
    import MachO
#else
    import MachOKitC
#endif
import XcodeGraph

extension BinaryArchitecture {
    /// An array of `(cpu_type_t, cpu_subtype_t)` pairs representing this architecture.
    private var pairs: [(cpu_type_t, cpu_subtype_t)] {
        switch self {
        case .x8664:
            return [
                (CPU_TYPE_X86_64, CPU_SUBTYPE_X86_64_ALL),
                (CPU_TYPE_X86_64, CPU_SUBTYPE_X86_64_H),
            ]
        case .i386:
            return [
                (CPU_TYPE_X86, CPU_SUBTYPE_X86_ALL),
            ]
        case .armv7:
            return [
                (CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7),
            ]
        case .armv7s:
            return [
                (CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7S),
            ]
        case .armv7k:
            return [
                (CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7K),
            ]
        case .arm64:
            return [
                (CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL),
            ]
        case .arm64e:
            return [
                (CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64E),
            ]
        case .arm6432:
            return [
                (CPU_TYPE_ARM64_32, CPU_SUBTYPE_ARM64_32_ALL),
                (CPU_TYPE_ARM64_32, CPU_SUBTYPE_ARM64_32_V8),
            ]
        }
    }

    /// Builds a single dictionary mapping `(cputype, cpusubtype)` to `BinaryArchitecture`.
    ///
    /// This is computed once by enumerating all enum cases and collecting their pairs.
    private static let architectureMap: [CPUIdentifier: BinaryArchitecture] = {
        var map = [CPUIdentifier: BinaryArchitecture]()
        for arch in Self.allCases {
            for (cputype, subtype) in arch.pairs {
                map[CPUIdentifier(cputype: cputype, cpusubtype: subtype)] = arch
            }
        }
        return map
    }()

    /// Initializes a `BinaryArchitecture` from `(cputype, cpusubtype)`.
    ///
    /// If not found in `architectureMap`, returns `nil`.
    public init?(cputype: cpu_type_t, subtype: cpu_subtype_t) {
        let key = CPUIdentifier(cputype: cputype, cpusubtype: subtype)
        // CPU_SUBTYPE_ANY is not available in MachOKitC
        #if canImport(MachO)
            let fallbackKey = CPUIdentifier(cputype: cputype, cpusubtype: CPU_SUBTYPE_ANY)
            guard let architecture = Self.architectureMap[key] ?? Self.architectureMap[fallbackKey] else {
                return nil
            }
        #else
            guard let architecture = Self.architectureMap[key] else {
                return nil
            }
        #endif
        self = architecture
    }
}

/// A small Hashable struct to store `(cputype, cpusubtype)` pairs as dictionary keys.
private struct CPUIdentifier: Hashable, Sendable {
    let cputype: cpu_type_t
    let cpusubtype: cpu_subtype_t
}
