# iOS app with a static framework using xcstrings in buildable folders

A workspace with an application that depends on a static framework containing `.xcstrings` string catalog resources, where the
framework target uses `buildableFolders` instead of explicit `sources` and `resources`. This fixture reproduces the stale-string
regression from issue #10325 and verifies that Xcode does not mark strings as stale during build when the static framework uses a
companion resource bundle.

```
Workspace:
  - App:
    - App (iOS app)
  - StaticFramework:
    - StaticFramework (static iOS framework)
    - StaticFramework_StaticFramework (iOS bundle)
```

Dependencies:

- App -> StaticFramework
- StaticFramework -> StaticFramework_StaticFramework
