@_implementationOnly import Foundation

func dumpIfNeeded(_ entity: some Encodable) {
    guard !ProcessInfo.processInfo.arguments.isEmpty,
          ProcessInfo.processInfo.arguments.contains("--tuist-dump")
    else { return }
    let encoder = JSONEncoder()
    // swiftlint:disable:next force_try
    let data = try! encoder.encode(entity)
    let manifest = String(data: data, encoding: .utf8)!
    print("TUIST_MANIFEST_START")
    print(manifest)
    print("TUIST_MANIFEST_END")
}
