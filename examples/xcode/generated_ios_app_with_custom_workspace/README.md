# iOS app with a custom workspace

iOS with a few projects and a `Workspace.swift` manifest file.

The workspace manifest defines:

- glob patterns to list projects
- glob patterns to include documentation files
- folder reference to directory with html files

The App's project manifest leverages `additionalFiles` that:

- defines glob patterns to include documentation files
- includes a Swift `Danger.swift` file that shouldn't get included in any build phase
- defines folder references to a directory with json files