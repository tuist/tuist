import Foundation
import ProjectAutomation

let task = Task(
    options: [
        .option("file-name"),
    ]
) { options in
    let fileName = options["file-name"] ?? "file"
    try "File created with a task".write(
        to: URL(fileURLWithPath: "\(fileName).txt"),
        atomically: true,
        encoding: .utf8
    )
    print("File created!")
}
