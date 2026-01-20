# iOS app with static frameworks


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