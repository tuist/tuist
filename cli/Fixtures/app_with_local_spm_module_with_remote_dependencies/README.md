# Application wih Local SPM Module with Remote Dependencies

This example contains a project that depends upon a local SPM module (`LocalSwiftPackage`) colocated within this directory.

This project does NOT contain any direct remote dependencies.
However, `LocalSwiftPackage` DOES have remote dependencies.

This example application exists to ensure that package resolution occurs even in the case of solely transitive remote dependencies.