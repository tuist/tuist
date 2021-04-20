import ProjectDescription
import Foundation

let tasks: Tasks = [
    .task(
        "create-file",
        options: [
            .optional("fileName")
        ]
    ) { options in
        let fileName = options["fileName"] ?? "file"
        try "File created with a task".write(
            to: URL(fileURLWithPath: "\(fileName).txt"),
            atomically: true,
            encoding: .utf8
        )
    }
]
