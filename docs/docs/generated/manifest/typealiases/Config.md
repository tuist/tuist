**TYPEALIAS**

# `Config`

```swift
public typealias Config = Tuist
```

The configuration of your environment.

Tuist can be configured through a shared `Tuist.swift` manifest.
When Tuist is executed, it traverses up the directories to find `Tuist.swift` file.
Defining a configuration manifest is not required, but recommended to ensure a consistent behaviour across all the projects
that are part of the repository.

The example below shows a project that has a global `Tuist.swift` file that will be used when Tuist is run from any of the
subdirectories:

```bash
/Workspace.swift
/Tuist.swift # Configuration manifest
/Framework/Project.swift
/App/Project.swift
```

That way, when executing Tuist in any of the subdirectories, it will use the shared configuration.

The snippet below shows an example configuration manifest:

```swift
import ProjectDescription

let tuist = Config(project: .tuist(generationOptions: .options(resolveDependenciesWithSystemScm: false)))

```