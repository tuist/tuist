# Manifest files

## Project.swift

Projects are defined in `Project.swift` which we refer to as manifest files. Manifests need to import the framework `ProjectDescription` which contains all the classes and enums that are available for you to describe your projects. The snippet below shows an example project manifest:

```swift
let project = Project(name: "MyProject",
                      targets: [
                          Target(name: "App",
                                 platform: .iOS,
                                 product: .app,
                                 bundleId: "io.tuist.App",
                                 infoPlist: "Config/App-Info.plist",
                                 sources: "Sources/**",
                                 dependencies: [
                                     .project(target: "Framework1", path: "../Framework1"),
                                     .project(target: "Framework2", path: "../Framework2"),
                          ])
])
```

### Project

A `Project.swift` should initialize a variable of type `Project.swift`. It can take any name, although we recommend to stick to `project`. A project accepts the following attributes:

- **Name:** Name of the project. It's used to determine the name of the generated Xcode project.
- **Targets:** It contains the list of targets that belong to the project. Read more [about targets](#target)
- **Settings (optional):** Read more about [settings](#settings)

> **Note:** All the relative paths in the project manifest are relative to the folder that contains the manifest file.

### Target

Each target in the list of project targets can be initialized with the following attributes:

- **Name:** The name of the target. The Xcode project target and the derivated product take the same name.
- **Platform:** The platform the target product is build for. The following products are supported:
  - **.app:** An application
  - **.staticLibrary:** A static library.
  - **.dynamicLibrary:** A dynamic library.
  - **.framework:** A dynamic framework.
  - **.unitTests:** A unit tests bundle.
  - **.uiTests:** A UI tests bundle.
- **BundleID:** The product bundle identifier.
- **InfoPlist:** Relative path to the `Info.plist`.
- **Sources:** List of sources to be compiled by the target. The attribute can be any of the following types:

  - **String:** A file or glob pattern _(e.g. `Sources/**`)_
  - **[String]:** A list of files or list of glob patterns _(e.g. `["Sources/**"]`)_

- **Resources (optional):** List of resources to be included in the product bundle. The types that it can take are the same as the `sources` attribute.
- **Headers (optional):** Target headers. It accepts a `Header` type that is initialized with the following attributes:

  - **Public:** Relative path to the folder that contains the public headers.
  - **Private:** Relative path to the folder that contains the private headers.
  - **Project:** Relative path to the folder that contains the project headers.

- **Entitlements (optional):** Relative path to the entitlements file.
- **Actions (optional):** Target actions allow defining extra script build phases. It's an array of `TargetAction` objects that can be initialized with any of the following static functions:

  - **pre(tool:):** Runs the binary with the given name before the default target build phases.
  - **pre(path:):** Runs the binary at the given path before the default target build phases.
  - **post(tool:):** Runs the binary with the given name after the default target build phases.
  - **post(path:):** Runs the binary at the given path after the default target build phases.

> Note that Tuist verifies whether the launch path is valid and fail otherwise.

- **Dependencies (optional):** You can read more about dependencies [here](./dependencies.md)
- **Settings (optional):** Read more about [settings](#settings)

- **CoreDataModels (optional):** An array of `CoreDataModel` objects. A `CoreDataModel` is an special type of resource that requires the following two attributes:
  - **Path:** Relative path to the Core Data model.
  - **CurrentVersion:** Current version without the extension.
- **Environment (optional):** It's a `[String: String]` to defined variables that will be set to the scheme that Tuist automatically generates for the target.

### Settings

A `Settings` object contains an optional dictionary with build settings and relative path to an `.xcconfig` file. It is initialized with the following attributes:

- **Base (optional):** A `[String: String]` with build settings that are inherited from all the configurations.
- **Debug (optional):** The debug configuration settings. The settings are initialized with `.settings([String: String], xcconfig: String)` where the first argument are the build settings and the second a relative path to an xcconfig file. Both arguments are optionals.
- **Release (optional):** Same as debug but for the release configuration.
