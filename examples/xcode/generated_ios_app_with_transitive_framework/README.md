# iOS app with a transitive framework

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