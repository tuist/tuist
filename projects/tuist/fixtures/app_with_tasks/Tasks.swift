import ProjectDescription
import Foundation

let tasks: Tasks = [
    .task("create-file") {
        try "File created with a task".write(
            to: URL(fileURLWithPath: "file.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
]