# BREAKME

This document lists breaking changes to introduce in the next major version of the project. Every change must include what needs to be changed, and the rationale behind it.

## Changes

### Change the default behavior to include test targets of local package dependencies. 

When generating a project with local swift package dependencies, it is common to include test targets of local swift packages by default.

#### What needs to be changed
- Set the default value of `includeLocalPackageTestTargets` to `true` and update associated documentation comments.
