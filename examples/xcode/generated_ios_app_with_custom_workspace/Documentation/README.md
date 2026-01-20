# README


## What can you do?

Reference url docs [Tuist][0]

[0]:https://docs.tuist.io

- Note: Set notes

- Important: Important Notes

+ Callout(Callout example): description
Continuing callout


```Swift
import ProjectDescription

let workspace = Workspace(
    name: "Workspace",
    projects: [
        "App",
        "Frameworks/**",
    ],
    additionalFiles: [
        "Documentation/**",
        .folderReference(path: "Website"),
    ],
    generationOptions: .options(enableAutomaticXcodeSchemes: false,
                                renderMarkdownReadme: true)
)
```
[View in Source](x-source-tag://Window)
