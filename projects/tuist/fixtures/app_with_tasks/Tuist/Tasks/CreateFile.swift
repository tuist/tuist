import ProjectAutomation
import ProjectAutomationHelpers
import Foundation

let task = Task(
    options: [
        .option("file-name"),
    ]
) { options in
    let fileName = options["file-name"] ?? "file"
    try "File created with a task".write(
        to: "\(fileName).txt"
    )
    print("File created!")
}
