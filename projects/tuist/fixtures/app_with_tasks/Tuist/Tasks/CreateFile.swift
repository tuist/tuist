import ProjectAutomation
import Foundation

let task = Task(
    options: [
        .option("file-name"),
    ]
) { options, graph in
    let fileName = options["file-name"] ?? "file"
    print(graph)
    try "File created with a task".write(
        to: URL(fileURLWithPath: "\(fileName).txt"),
        atomically: true,
        encoding: .utf8
    )
    print("File created!")
}
