# Fixtures

This folder contains sample projects we use in the integration and acceptance tests.
Please keep this keep in alphabetical order.

## invalid_workspace_manifest_name

Contains a single file `Workspac.swift`, incorrectly named workspace manifest file.

## ios_app_with_custom_workspace

Contains a few projects and a `Workspace.swift` manifest file. 

The workspace manifest defines:

- glob patterns to list projects
- glob patterns to list additional files
- folder references

## ios_app_with_tests

Simple app which includes a setup manifest.

The setup action simply installs a dummy tool (file) to `/tmp`

Can be tested by running `tuist up`.

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
```

Dependencies:
  - App -> Framework1
  - App -> Framework2
  - Framework1 -> Framework2

## ios_app_with_static_libraries

This application provides a top level application with two static library dependencies. The first static library dependency has another static library dependency so that we are able to test how tuist handles the transitiveness of the static libraries in the linked frameworks of the main app.

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

Dependencies:
  - App -> A
  - A -> B

## ios_app_with_static_frameworks

Same as `ios_app_with_static_libraries` except using static frameworks instead of libraries.

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

Dependencies:
  - App -> A
  - A -> B

## ios_app_with_tests

Simple app with tests.
