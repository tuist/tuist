# Generation-time configuration

Learn how to leverage environment variables that can be read from the manifest files.

There are certain scenarios where you might need to dynamically change the generated project's definition when invoking Tuist at generation time. For example, if you are building a white-label app, you might want to use the same project structure, but adjust some attributes in a per-app basis. For example, the name of the app.

### Using Tuist environment variables

To facilitate that, Tuist allows passing configuration through environment variables that can be accessed from the manifest files. For example:

```bash
TUIST_APP_NAME=MyApp tuist generate
```

If you want to pass multiple environment variables just separate them with a space. For example:

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

Variables can be accessed using the `Environment` type. Any variables following the convention `TUIST_XXX` defined in the environment or passed to Tuist when running commands will be accessible using the `Environment` type.
The following example shows how we access the `TUIST_APP_NAME` variable:

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

| Case       | Description                                                                                                                                                     |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.string`  | Used when the variable represents a string.                                                                                                                     |

You can also retrieve the string or boolean Environment variable using either of the helper methods defined below, these methods require a default value to be passed to ensure the user gets consistent results each time. This avoids the need to define the function appName() defined above.

```swift
Environment.appName.getString(default: "TuistApp")
```

```swift
Environment.isCI.getBoolean(default: false)
```
