# Fixtures

This folder contains sample projects we use in the integration and acceptance tests.
Please keep this list in alphabetical order.

## app_with_organization_name_project

An iOS app where the organization name is defined at the `Project` level.

## framework_with_environment_variables

A framework project that leverages environment variables to change the name of the framework.

## invalid_manifest

A project with an invalid manifest.

## invalid_workspace_manifest_name

Contains a single file `Workspac.swift`, incorrectly named workspace manifest file.

## ios_app_with_actions

An iOS app with a target that has pre and post actions.

## ios_app_with_build_variables

An iOS app with a Xcode build variables defined in pre action.

## ios_app_with_coredata

A simple iOS app with a Core Data model and Mapping Model (.xcmappingmodel).

## ios_app_with_custom_workspace

Contains a few projects and a `Workspace.swift` manifest file.

The workspace manifest defines:

- glob patterns to list projects
- glob patterns to include documentation files
- folder reference to directory with html files

The App's project manifest leverages `additionalFiles` that:

- defines glob patterns to include documentation files
- includes a Swift `Danger.swift` file that shouldn't get included in any build phase
- defines folder references to a directory with json files

## ios_app_with_extensions

Sample application with extension targets.

## ios_app_with_framework_and_resources

A workspace with an application that includes resources.

```
Workspace:
  - App:
    - MainApp (iOS app)
    - MainAppTests (iOS unit tests)
  - Framework1:
    - Framework1 (dynamic iOS framework)
  - StaticFramework
    - StaticFramework (static iOS framework)
    - StaticFrameworkResources (iOS bundle)
```

Dependencies:

- App -> Framework1
- App -> StaticFramework
- App -> StaticFrameworkResources

## ios_app_with_framework_linking_static_framework

An example project demonstrating an iOS application linking a dynamic framework which itself depends on a static framework with transitive static dependencies.

Only `Framework1.framework` should be linked and included into App, everything else should be statically linked into the Framework1 executable.

```
Workspace:
  - App:
    - MainApp (iOS app)
    - MainAppTests (iOS unit tests)
  - Framework1:
    - Framework1 (dynamic iOS framework)
    - Framework1Tests (iOS unit tests)
  - Framework2:
    - Framework2 (static iOS framework)
    - Framework2Tests (iOS unit tests)
  - Framework3:
    - Framework3 (static iOS framework)
    - Framework3Tests (iOS unit tests)
  - Framework4:
    - Framework4 (static iOS framework)
    - Framework4Tests (iOS unit tests)
```

Dependencies:

- App -> Framework1
- Framework1 -> Framework2
- Framework1 -> Framework3
- Framework3 -> Framework4

## ios_app_with_frameworks

Slightly more complicated project consists of an iOS app and few frameworks.

```
Workspace:
  - App:
    - MainApp (iOS app)
    - MainAppTests (iOS unit tests)
  - Framework1:
    - Framework1 (dynamic iOS framework)
    - Framework1Tests (iOS unit tests)
  - Framework2:
    - Framework2 (dynamic iOS framework)
    - Framework2Tests (iOS unit tests)
  - Framework3:
    - Framework3 (dynamic iOS framework)
  - Framework4:
    - Framework4 (dynamic iOS framework)
  - Framework5:
    - Framework5 (dynamic iOS framework)
```

Dependencies:

- App -> Framework1
- App -> Framework2
- Framework1 -> Framework2
- Framework2 -> Framework3
- Framework3 -> Framework4
- Framework4 -> Framework5

## ios_app_with_helpers

A basic iOS app that has some manifest bits extracted into helpers.

## ios_app_with_incompatible_dependencies

An iOS app that has a dependency with a dependency with a framework for macOS.

## ios_app_with_incompatible_xcode

An iOS app whose Config file requires an Xcode version that is not available in the system.

## ios_app_with_local_swift_package

An iOS application with local Swift package.

## ios_app_with_multi_configs

An workspace that contains an application and frameworks that leverage multiple configurations (Debug, Beta and Release) each of which also has an associated xcconfig file within `ConfigurationFiles`.

## ios_app_with_remote_swift_package

An iOS application with remote Swift package.

## ios_app_with_sdk

An application that contains an application target that depends on system libraries and frameworks (`.framework` and `.tbd`).

One of the dependencies is declared as `.optional` i.e. will be linked weakly.

## ios_app_with_static_frameworks

This fixture contains an application that depends on static frameworks, both directly and transitively.

```
Workspace:
  - App:
    - MainApp (iOS app)
    - MainAppTests (iOS unit tests)
  - Modules
    - A:
      - A (static framework iOS)
      - ATests (iOS unit tests)
    - B:
      - B (static framework iOS)
      - BTests (iOS unit tests)
    - C:
      - C (static framework iOS)
      - CTests (iOS unit tests)
    - D:
      - D (dynamic framework iOS)
```

A standalone `Prebuilt` project is used to generate a prebuilt static framework:

```
- Prebuilt
  - PrebuiltStaticFramework (static framework iOS)
```

Dependencies:

- App -> A
- App -> C
- App -> PrebuiltStaticFramework
- A -> B
- A -> C
- C -> D

Note: to re-create `PrebuiltStaticFramework.framework` run `ios_app_with_static_frameworks/Prebuilt//build.sh`

## ios_app_with_static_libraries

This application provides a top level application with two static library dependencies. The first static library dependency has another static library dependency so that we are able to test how Tuist handles the transitiveness of the static libraries in the linked frameworks of the main app.

```
Workspace:
  - App:
    - MainApp (iOS app)
    - MainAppTests (iOS unit tests)
  - A:
    - A (static library iOS)
    - ATests (iOS unit tests)
  - B:
    - B (static library iOS)
    - BTests (iOS unit tests)
```

A standalone C project is used to generate a prebuilt static library:

```
  - C:
    - C (static library iOS)
    - CTests (iOS unit tests)
```

Dependencies:

- App -> A
- A -> B
- A -> prebuild C (libC.a)

Note: to re-create `libC.a` run `ios_app_with_static_libraries/Modules/C/build.sh`

## ios_app_with_static_library_and_package

An iOS application that depends on static library that depends on Swift package where static library is defined first.

Note: to re-create `PrebuiltStaticFramework.framework` run `ios_app_with_static_library_and_package/Prebuilt/build.sh`

## ios_app_with_tests

Simple app with tests, which includes a setup manifest and uses `.notGrouped` autogenerated schemes.

## ios_app_with_transitive_framework

```
Workspace:
  - App:
    - MainApp (iOS app)
    - MainAppTests (iOS unit tests)
  - Framework1:
    - Framework1 (dynamic iOS framework)
    - Framework1Tests (iOS unit tests)
```

A standalone Framework2 project is used to generate a prebuilt dynamic framework:

```
  - Framework2:
    - Framework2 (dynamic iOS framework)
```

Dependencies:

- App -> Framework1
- Framework1 -> Framework2 (prebuilt)

Note: to re-create `Framework2.framework` run `ios_app_with_transitive_framework/Framework2/build.sh`

## ios_app_with_xcframeworks

```
Workspace:
  - App:
    - MainApp (iOS app)
    - MainAppTests (iOS unit tests)
  - MyFramework:
    - MyFramework (dynamic iOS framework)
  - MyStaticFramework:
    - MyStaticFramework (static iOS framework)
  - MyStaticLibirary:
    - MyStaticLibrary (static iOS libraries)
```

An example of an application which depends on prebuilt `.xcframework`s.

The `.xcframework` can be obtained by running the `build.sh` script within the each of the xcframework directories
e.g. `ios_app_with_xcframeworks/XCFrameworks/MyFramework/build.sh`.

## ios_workspace_with_dependency_cycle

An example of a workspace that has a dependency cycle between targets in different projects.

## macos_app_with_extensions

The project contains a macOS app with various types of extensions.

## manifest_with_logs

A project that contains logs to verify that the logs are forwarded by Tuist.
