# Cached framework statically linking a package with resources

An iOS dynamic framework statically links an external package whose library has resources, and a
hostless unit test target exercises the package's `Bundle.module` through the framework.

```
Project:
  - Framework (dynamic iOS framework)
  - FrameworkTests (hostless unit tests asserting the package resource resolves at runtime)
External:
  - ResourcesLib (static framework with resources, from the local ResourcesPackage)
  - ResourcesPackage_ResourcesLib (bundle, synthesized)
```

The package's code is linked into `Framework.framework`, so at runtime `Bundle.module` looks for
`ResourcesPackage_ResourcesLib.bundle` inside `Framework.framework` and in the built products
directory next to it. The hostless test bundle is not one of those locations, so the resource
bundle has to be built into the products directory even when `Framework` comes from the binary
cache.

Dependencies:

- Framework -> ResourcesLib
- FrameworkTests -> Framework
