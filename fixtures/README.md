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
