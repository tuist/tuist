import Foundation

func dumpIfNeeded<E: Encodable>(_ entity: E) {
    if CommandLine.argc > 0 {
        if CommandLine.arguments.contains("--dump") {
            let data = try! JSONEncoder().encode(entity)
            let string = String(data: data, encoding: .utf8)!
            print(string)
        }
    }
}
