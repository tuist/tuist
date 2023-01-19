---
title: Using plugins
slug: '/plugins/using-plugins'
description: Learn how to extend Tuist with plugins.
---

### Plugins

Plugins are meant to be separate and isolated directories, each containing code used to extend existing Tuist functionality.
You may use plugins that exist at a path local to your machine or at a git source URL to enable sharing and version control across multiple projects. They are fetched by running `tuist fetch`. If you add plugin to your project you can not generate it without fetching. 

### Adding plugins

In order to tell Tuist you'd like to use plugins in your project, you can start by defining the plugins in the [`Config.swift`](manifests/config.md) manifest.

```swift
import ProjectDescription

let config = Config(
    plugins: [
        .local(path: "/Plugins/MyPlugin"),
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ]
)
```

By defining plugins in the [`Config.swift`](manifests/config.md) manifest Tuist is able to collect, cache and use your plugins to add or extend functionality.

#### Local plugin

Local plugins are stored relative to the machine generating the project. You can tell Tuist to find them at a given [`Path`](manifests/project.md).

```swift
PluginLocation.local(path: "/Plugins/MyPlugin")
PluginLocation.local(path: .relativeToCurrentFile("MyOtherPlugin/"))
PluginLocation.local(path: .relativeToManifest("../DevelopmentPlugin"))
```

:::note Local plugins will not work for [tasks](guides/task.md). If you want to run them locally, either add the built executable to your `$PATH` or run via plugin command - learn more about it [here](commands/plugin.md)
:::

#### Remote plugin

Remote plugins are stored on a remote server and can be downloaded by Tuist and shared across multiple projects.

##### Git

A common place to store plugins is in a git repository which is uploaded to a remote server. You can specify where to download the plugin as well as what version of the plugin to take.
This allows you to version your plugins and share them with others.

Optionally, you can also specify a directory where the plugin is located, in case it's not at the root of the repository.

You can choose to collect a plugin at a specific git tag:

```swift
PluginLocation.git(url: "https://url/to/plugin.git", tag: "1.0.0"),
```

You may also collect a plugin at a specific git sha:

```swift
PluginLocation.git(url: "https://url/to/plugin.git", sha: "e34c5ba")
```

The [`Plugin.swift`](plugins/creating-plugins.md) manifest in a git repository should be located at the root of the repository.

### Example

Let's say we have a plugin called `MyTuistPlugin`. This plugin is designed to add functionality to `ProjectDescription`, in this example the plugin will add a new method to `Project` which allow us to define an application.
This plugin is stored in git on some remote server, and we'd like to use version `1.0.0` of the plugin.

We must first configure Tuist to use our plugin, we can do that by adding the plugin to the [`Config.swift`](manifests/config.md) manifest.

```swift
import ProjectDescription

let config = Config(
    plugins: [
        .git(url: "https://url/to/MyTuistPlugin", tag: "1.0.0")
    ]
)
```

After plugins have been declared in `Config.swift`, you need to fetch them by running [`tuist fetch`](commands/dependencies.md#fetching). 

#### Tasks

To use a task plugin, simply import the plugin in `Config.swift` and it will be automatically available by running `tuist my-plugin-task`.
You can read more about tasks [here](guides/task.md).

#### Project description helpers

You can import a project description helper plugin with the name defined in the [`Plugin.swift`](plugins/creating-plugins.md) manifest, which can then be used in a project manifest:

```swift
import ProjectDescription
import MyTuistPlugin

let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
