---
title: Dynamic configuration
description: Learn how how to use environment variables to dynamically configure your project.
---

# Dynamic configuration

There are certain scenarios where you might need to dynamically configure your project at generation time. For example, you might want to change the name of the app, the bundle identifier, or the deployment target based on the environment where the project is being generated. Tuist supports that via environment variables, which can be accessed from the manifest files.

## Configuration through environment variables

Tuist allows passing configuration through environment variables that can be accessed from the manifest files. For example:

```bash
TUIST_APP_NAME=MyApp tuist generate
```

If you want to pass multiple environment variables just separate them with a space. For example:

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## Reading the environment variables from manifests

Variables can be accessed using the [`Environment`](/references/project-description/enums/environment) type. Any variables following the convention `TUIST_XXX` defined in the environment or passed to Tuist when running commands will be accessible using the `Environment` type. The following example shows how we access the `TUIST_APP_NAME` variable:

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

Accessing variables returns an instance of type `Environment.Value?` which can take any of the following values:

| Case | Description |
| --- | --- |
| `.string(String)` | Used when the variable represents a string. |

You can also retrieve the string or boolean `Environment` variable using either of the helper methods defined below, these methods require a default value to be passed to ensure the user gets consistent results each time. This avoids the need to define the function appName() defined above.

::: code-group

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
:::