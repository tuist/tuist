# Fixtures

This folder contains sample projects we use in the integration and acceptance tests.
Please keep this keep in alphabetical order.

## app_with_frameworks

Slightly more complicated project consists of an iOS app and few frameworks.

#### Structure

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

## app_with_tests

Simple app with tests.

## invalid_workspace_manifest_name

Contains a single file `Workspac.swift`, incorrectly named workspace manifest file.

## ios_app_with_multiple_configurations

This workspace contains 3 projects and a set of shared xcconfig files within `configs`. Each of the projects declares multiple configurations / build settings at different levels.

```
Workspace:
  - App:
    - MainApp (iOS app)
    - MainAppTests (iOS unit tests)
  - configs:
    - beta.xcconfig
    - debug.xcconfig
    - release.xcconfig
    - shared.xcconfig
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

Config files:
  - beta.xcconfig -> shared.xcconfig
  - debug.xcconfig -> shared.xcconfig
  - release.xcconfig -> shared.xcconfig


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
