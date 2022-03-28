Resolves https://github.com/tuist/tuist/issues/YYY
Request for comments document (if applies):

### Short description 📝

> Describe here the purpose of your PR.

### How to test the changes locally 🧐

> Include a set of steps for the reviewer to test the changes locally.

### Checklist ✅

- [ ] The code architecture and patterns are consistent with the rest of the codebase.
- [ ] The changes have been tested following the [documented guidelines](https://docs.tuist.io/contributors/testing-strategy/).
- [ ] The PR includes the label `changelog:added`, `changelog:fixed`, or `changelog:changed`, whenever it should be included in the “Added”, “Fixed” or “Changed” section of the CHANGELOG. Note: when included in the CHANGELOG, the title of the PR will be used as entry, please make sure it is clear and suitable.
- [ ] In case the PR introduces changes that affect users, the documentation has been updated.
- [ ] In case the PR introduces changes that affect how the cache artifact is generated starting from the `TuistGraph.Target`, the `Constants.cacheVersion` has been updated.
