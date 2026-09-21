use std::env;
use std::path::PathBuf;

// Links the Swift `TuistEmbed` dynamic library built by SwiftPM at the repository root.
// Override the directory with TUIST_EMBED_LIB_DIR; defaults to `<repo>/.build/<profile>`.
fn main() {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let swift_config = env::var("TUIST_EMBED_SWIFT_CONFIGURATION").unwrap_or_else(|_| "debug".into());
    let lib_dir = env::var("TUIST_EMBED_LIB_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| manifest_dir.join("..").join(".build").join(&swift_config));

    println!("cargo:rerun-if-env-changed=TUIST_EMBED_LIB_DIR");
    println!("cargo:rerun-if-env-changed=TUIST_EMBED_SWIFT_CONFIGURATION");
    println!("cargo:rustc-link-search=native={}", lib_dir.display());
    println!("cargo:rustc-link-lib=dylib=TuistEmbed");
    // The Swift code finds ProjectDescription, templates and resource bundles next to the binary,
    // so the dylib ships beside the executable, as in the release bundle.
    println!("cargo:rustc-link-arg=-Wl,-rpath,@executable_path");
    // Debug builds, test binaries included, can also load the library where SwiftPM
    // built it. Release binaries rely on the bundle layout only.
    if env::var("PROFILE").as_deref() == Ok("debug") {
        println!("cargo:rustc-link-arg=-Wl,-rpath,{}", lib_dir.display());
    }
    println!("cargo:rustc-link-arg=-Wl,-rpath,/usr/lib/swift");
}
