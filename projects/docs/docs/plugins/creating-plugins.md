---
title: Creating plugins
slug: '/plugins/creating-plugins'
description: Learn how to create plugins for Tuist.
---

A plugin to Tuist is a directory with a `Plugin.swift` manifest. This manifest is used to define specific attributes of a plugin.

### Plugin.swift manifest

```swift
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```

### Project description helpers

Project description helpers can be used to extend Tuist's functionality: Tuist automatically compiles the sources and allows it to be imported during project generation.

In order for Tuist to find the source files for these helpers they must be placed in the same directory as the `Plugin.swift` manifest and in a
directory called `ProjectDescriptionHelpers`

```
.
├── ...
├── Plugin.swift
├── ProjectDescriptionHelpers
└── ...
```

The `.swift` files in the `ProjectDescriptionHelpers` directory are collected and compiled and can then be imported using the name
of the plugin:

```swift
import ProjectDescription
import MyPlugin

...
```

### Templates

Template plugins can be used to share & reuse custom templates. Tuist will collect all templates from defined plugins and allow them to be used with commands like [`tuist scaffold`](commands/scaffold.md).

In order for Tuist to locate the templates for a plugin, they must be placed in the same directory as the `Plugin.swift` manifest and in a directory named `Templates`.

```
.
├── ...
├── Plugin.swift
├── Templates
└── ...
```

### Tasks

Tasks represent arbitrary tasks which can be run via tuist. For more context, continue [here](guides/task.md) where you will also find documentation for the `ProjectAutomation` framework.

To create a task plugin, start by adding a `Package.swift` and adding your CLI executable with `tuist` prefix, such as:
```swift
let package = Package(
    name: "MyPlugin",
    products: [
        .executable(name: "tuist-my-cli", targets: ["tuist-my-cli"]),
    ],
    targets: [
        .target(
            name: "tuist-my-cli",
        ),
    ]
)
```

For easier development and help with publishing your plugin, use `tuist plugin` - you can read more about it [here](commands/plugin.md).

To publish a plugin with tasks, you will need to run `tuist plugin archive` and then create a Github release with the created `.zip` as an artifact.

## ResourceSynthesizers

ResourceSynthesizer plugins are for sharing & reusing templates for [synthesizing resources](guides/resources.md). If you want to use one of the predefined resource synthesizers, the template must also adhere to a specific naming.

For example if you initialize `ResourceSynthesizer` with `.strings(plugin: "MyPlugin")` then the template must be called `Strings.stencil`.

There are more types, so the naming is:

- `strings` => `Strings.stencil`
- `assets` => `Assets.stencil`
- `plists` => `Plists.stencil`
- `fonts` => `Fonts.stencil`
- `coreData` => `CoreData.stencil`
- `interfaceBuilder` => `InterfaceBuilder.stencil`
- `json` => `JSON.stencil`
- `yaml` => `YAML.stencil`

You can also create a `ResourceSynthesizer` with `.custom`. In this case the template should be of the same name as `resourceName`.

In order for Tuist to locate the templates for a plugin, they must be placed in the same directory as the `Plugin.swift` manifest and in a directory named `ResourceSynthesizers`.

```
.
├── ...
├── Plugin.swift
├── ResourceSynthesizers
├───── Strings.stencil
├───── Plists.stencil
├───── CustomTemplate.stencil
└── ...
```

If you'd like to provide a type-safe way for users of your plugin to use your custom resource synthesizers you can use an extension like:

```swift
extension ResourceSynthesizer {
    public static func myPluginStrings() -> Self {
        .strings(plugin: "MyPlugin")
    }
}

extension Array where Element == ResourceSynthesizer {
    public static var `default`: Self {
        [
            .myPluginStrings(),
            .myPluginPlists(),
            ...
        ]
    }
}
```

### Example

Let's walk through creating a custom plugin for Tuist! Our plugin will be named `MyTuistPlugin` and we want to add a new method to `Project` that will
allow other developers to easily create a project for an iOS app.

#### Create the directory

We must first create a directory for our plugin, it may look something like:

```
MyTuistPlugin/
├── Plugin.swift
├── ProjectDescriptionHelpers
```

#### Create the Plugin manifest

Next we create the `Plugin.swift` manifest and give our plugin a name:

```swift
// Plugin.swift
import ProjectDescription

let plugin = Plugin(name: "MyTuistPlugin")
```

#### Add project description helpers

In order for our plugin to be useful we decide we want to add custom project description helpers so that other developers can easily make an iOS app project.
For example we can create a file named `Project+App.swift` and place it in a `ProjectDescriptionHelpers` directory next to the `Plugin.swift`

```swift
// Project+App.swift (in ProjectDescriptionHelpers/)
import ProjectDescription

public extension Project {
    static func app(name: String) -> Project {
        return Project(...)
    }
}
```

Notice how you label extensions, methods, classes and structs as `public` if you'd like them to be usable by others when they import your plugin.

#### Use the plugin

We can follow the [using plugins](plugins/using-plugins.md) to learn more about how to use plugins. For this example we may want to include the plugin and use it like so:

```swift
// Project.swift
import ProjectDescription
import MyTuistPlugin

let project = Project.app(name: "MyApp")
```

Notice how we import our plugin using the name defined in the `Plugin.swift` manifest and this now allows us to use the `app` method defined in the `ProjectDescriptionHelpers` of the plugin!
