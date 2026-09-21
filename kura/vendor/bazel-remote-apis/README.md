# Bazel Remote Apis for Rust

## Usage

To use in your project, add into `Cargo.toml`:

```toml
[dependencies]
bazel-remote-apis = "0.14.0"
```

Feature `serde` adds implementation of `serde::Serialize` and `serde::Deserialize` traits for protobuf types.

## Development

Protobuf files are vendored with [git-vendor](https://github.com/brettlangdon/git-vendor):

```bash
$ git vendor list
googleapis@master:
    name:   googleapis
    dir:    bzl-remote-apis/thirdparty/github.com/googleapis/googleapis
    repo:   https://github.com/googleapis/googleapis
    ref:    master
    commit: 351713de98ef863ad79e24e46a3d72c5f656d960

remote-apis@main:
    name:   remote-apis
    dir:    bzl-remote-apis/thirdparty/github.com/bazelbuild/remote-apis
    repo:   https://github.com/bazelbuild/remote-apis.git
    ref:    main
    commit: 080024152253a987d6bc4bcba4b20aa3484c1488
```

Build script is used to generate Rust source code from proto files into `src/generated`.

To update vendored dependencies and generate code run:

```bash
git vendor update googleapis
git vendor update bazel-remote-apis
cargo build --features codegen
```
