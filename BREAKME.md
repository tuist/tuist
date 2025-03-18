# BREAKME

This document lists breaking changes to introduce in the next major version of the project. Every change must include what needs to be changed, and the rationale behind it.

## Changes

### Change the default behavior to include test targets of local package dependencies. 

Tuist has historically generated only SPM targets directly used by downstream targets defined in the `Project.swift` without any unit tests, regardless whether the respective SPM packages were local or not. In [this](https://github.com/tuist/tuist/pull/6436) PR, we introduced a new `includeLocalPackageTestTargets` option in the `PackageSettings`, so that developers can opt-in to generating unit tests target of local SPM packages. Since local SPM packages are typically iterated on with the project that imports them, we believe the `includeLocalPackageTestTargets` should be turned on by default with an opt-out option, instead of being opt-in.

#### What needs to be changed
- Set the default value of `includeLocalPackageTestTargets` to `true` and update the relevant docs.
