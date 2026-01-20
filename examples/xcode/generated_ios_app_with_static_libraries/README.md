# iOS app with static libraries


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