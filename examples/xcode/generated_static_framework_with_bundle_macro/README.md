# Static framework using Foundation's #bundle macro

A project with a static framework that owns resources and reaches them through Foundation's
`#bundle` macro — both directly and as a caller-side default argument
([SE-0422](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0422-caller-side-default-argument-macro-expression.md)).

`#bundle` expands to `Bundle.module` only when the build system sets the
`SWIFT_MODULE_RESOURCE_BUNDLE_AVAILABLE` compilation condition for resource-bearing modules;
otherwise it falls back to a DSO-handle lookup that resolves to the main bundle for statically
linked code, where resources living in the companion `.bundle` are invisible.

```
Project:
  - ResourceLoader (static iOS framework, no resources, exposes an API with a #bundle default argument)
  - StaticFramework (static iOS framework with resources)
  - BundleMacro_StaticFramework (iOS bundle, synthesized)
  - StaticFrameworkTests (unit tests asserting the resource resolves at runtime)
```

Dependencies:

- StaticFramework -> ResourceLoader
- StaticFramework -> BundleMacro_StaticFramework
- StaticFrameworkTests -> StaticFramework
