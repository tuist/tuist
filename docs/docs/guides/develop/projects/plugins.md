---
title: Plugins
description: Learn how to create and use plugins in Tuist to extend its functionality.
---

# Plugins

Plugins are a tool to share and reuse Tuist artifacts across multiple projects. The following artifacts are supported:

- [Project description helpers](/guides/develop/projects/code-sharing) across multiple projects.
- [Templates](/guides/develop/projects/templates) across multiple projects.
- Tasks across multiple projects.
- [Resource accessor](/guides/develop/projects/synthesized-files) template across multiple projects

Note that plugins are designed to be a simple way to extend Tuist's functionality. Therefore there are **some limitations to consider**:

- A plugin cannot depend on another plugin.
- A plugin cannot depend on third-party Swift packages
- A plugin cannot use project description helpers from the project that uses the plugin.

If you need more flexibility, consider suggesting a feature for the tool or building your own solution upon Tuist's generation framework, [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

> [!WARNING] NON-ACTIVELY-MAINTAINED
> Our plugin infrastructure is not actively maintained. We are looking for contributors to help us improve it. If you are interested, please reach out to us on [Slack](https://slack.tuist.io/).

## Plugin types

### Project description helper plugin

A project description helper plugin is represented by a directory containing a `Plugin.swift` manifest file that declares the plugin's name and a `ProjectDescriptionHelpers` directory containing the helper Swift files.

::: code-group
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ProjectDescriptionHelpers
└── ...
```
:::

### Resource accessor templates plugin

If you need to share [synthesized resource accessors](/guides/develop/projects/synthesized-files#resource-accessors) you can use
this type of plugin. The plugin is represented by a directory containing a `Plugin.swift` manifest file that declares the plugin's name and a `ResourceSynthesizers` directory containing the resource accessor template files.


::: code-group
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ResourceSynthesizers
├───── Strings.stencil
├───── Plists.stencil
├───── CustomTemplate.stencil
└── ...
```
:::

The name of the template is the [camel case](https://en.wikipedia.org/wiki/Camel_case) version of the resource type:

| Resource type | Template file name |
| ------------- | ------------------ |
| Strings | Strings.stencil |
| Assets | Assets.stencil |
| Property Lists | Plists.stencil |
| Fonts | Fonts.stencil |
| Core Data | CoreData.stencil |
| Interface Builder | InterfaceBuilder.stencil |
| JSON | JSON.stencil |
| YAML | YAML.stencil |

When defining the resource synthesizers in the project, you can specify the plugin name to use the templates from the plugin:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Task plugin <Badge type="warning" text="deprecated" />

Tasks are `$PATH`-exposed executables that are invocable through the `tuist` command if they follow the naming convention `tuist-<task-name>`. In earlier versions, Tuist provided some weak conventions and tools under `tuist plugin` to `build`, `run`, `test` and `archive` tasks represented by executables in Swift Packages, but we have deprecated this feature since it increases the maintenance burden and complexity of the tool.

If you were using Tuist for distributing tasks, we recommend building your 
- You can continue using the `ProjectAutomation.xcframework` distributed with every Tuist release to have access to the project graph from your logic with `let graph = try Tuist.graph()`. The command uses sytem process to run the `tuist` command, and return the in-memory representation of the project graph.
- To distribute tasks, we recommend including the a fat binary that supports the `arm64` and `x86_64` in GitHub releases, and using [Mise](https://mise.jdx.dev) as an installation tool. To instruct Mise on how to install your tool, you'll need a plugin repository. You can use [Tuist's](https://github.com/asdf-community/asdf-tuist) as a reference.
- If you name your tool `tuist-{xxx}` and users can install it by running `mise install`, they can run it either invoking it directly, or through `tuist xxx`.

> [!NOTE] THE FUTURE OF PROJECTAUTOMATION
> We plan to consolidate the models of `ProjectAutomation` and `XcodeGraph` into a single backward-compatible framework that exposes the entirity of the project graph to the user. Moreover, we'll extract the generation logic into a new layer, `XcodeGraph` that you can also use from your own CLI. Think of it as building your own Tuist. 

## Using plugins

To use a plugin, you'll have to add it to your project's [`Config.swift`](/references/project-description/structs/config) manifest file:

```swift
import ProjectDescription


let config = Config(
    plugins: [
        .local(path: "/Plugins/MyPlugin")
    ]
)
```

If you want to reuse a plugin across projects that live in different repositories, you can push your plugin to a Git repository and reference it in the `Config.swift` file:

```swift
import ProjectDescription


let config = Config(
    plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ]
)
```

After adding the plugins, `tuist install` will fetch the plugins in a global cache directory.

> [!NOTE] NO VERSION RESOLUTION
> As you might have noted, we don't provide version resolution for plugins. We recommend using Git tags or SHAs to ensure reproducibility.

> [!TIP] PROJECT DESCRIPTION HELPERS PLUGINS
> When using a project description helpers plugin, the name of the module that contains the helpers is the name of the plugin
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```