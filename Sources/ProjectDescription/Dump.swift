import Foundation

func dumpIfNeeded(_ entity: JSONConvertible) {
    if CommandLine.argc > 0 {
        if CommandLine.arguments.contains("--dump") {
            print(entity.toJSON().toString())
        }
    }
}
