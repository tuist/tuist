import Framework

// The app target is not compiled by this suite — `tuist cache` only builds the
// cacheable Framework dependency, and `tuist generate` regenerates the project
// linking the cached xcframework. This source only needs to exist.
let greeting = Greeter().greeting()
