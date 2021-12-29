---
title: tuist exec
slug: '/commands/task'
description: 'Learn how to to automate arbitrary tasks with tuist Swift.'
---

When we write apps, it is often necessary to write some supporting code for e.g. releasing, downloading localizations, etc.
These are often written in Shell or Ruby which only a handful of developers on your team might be familiar with.
This means that these files are edited by an exclusive group and they are sort of "magical" for others.
We try to fix that by introducing a concept of "Tasks" where you can define custom commands - in Swift!

### Defining a task

To define a task, you can run `tuist edit` and then create a file `NameOfCommand.swift` in `Tuist/Tasks` directory.
Afterwards, you will need to define the task's options (if there are any) and the code that should be executed when the task is run.
Below you can find an example of the `CreateFile` task:

```swift
import ProjectAutomation
import Foundation

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
```

If you added this file to `Tuist/Tasks/CreateFile.swift`, you can run it by `tuist exec create-file --file-name MyFileName`.
The `Task` accepts two parameters - `options: [Option]` which defines the possible options of the task.
Then there is a parameter `task: ([String: String]) throws -> Void` which is a simple closure that is executed when the task is run.
Note that the closure has input of `[String: String]` -
this is a dictionary of options defined by the user where the key is the name of the option and value is the option's value.
