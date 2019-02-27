import Foundation

func dumpIfNeeded<E: Encodable>(_ entity: E) {
    if CommandLine.argc > 0 {
        if CommandLine.arguments.contains("--dump") {
            let encoder = JSONEncoder()
            // swiftlint:disable:next force_try
            let data = try! encoder.encode(entity)
            let string = String(data: data, encoding: .utf8)!
            print(string)
        }
    }
}
