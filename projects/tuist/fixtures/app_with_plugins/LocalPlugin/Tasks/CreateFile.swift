import Foundation
import ProjectAutomation

let task = Task { _ in
    try "File created with a plugin".write(
        to: URL(fileURLWithPath: "plugin-file.txt"),
        atomically: true,
        encoding: .utf8
    )
    print("File created with a plugin!")
}
