# iOS app with a framework and resources

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