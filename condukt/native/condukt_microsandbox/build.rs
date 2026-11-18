// Linker tweaks for the cdylib.
//
// On Linux, link the cdylib with `-Wl,-z,nodelete` so that `dlclose` does not
// unmap our shared object. Several transitive C dependencies pulled in
// through the microsandbox crate (aws-lc-sys, ring, sqlite3-sys, libcap-ng,
// bzip2-sys, zstd-sys) register `atexit` handlers at library load. If BEAM
// `dlclose`s the NIF during shutdown, those handlers still sit in libc's
// exit-handler table and point into the now-unmapped region the `.so`
// occupied. When libc later runs `__run_exit_handlers` it jumps to a
// page-aligned address inside the freed region and the process segfaults
// just before exit (observed on GHA Linux runners against beam.smp 28.3.1,
// thread `erts_sched_2`, crash address inside the .so's mapping range with
// no caller frame on the stack).
//
// `-z nodelete` tells the dynamic linker that the object is not eligible to
// be unloaded. `dlclose` becomes a no-op for it; the `.so` stays mapped until
// process exit, so all atexit handlers it registered remain callable. This is
// the same workaround `cryptography`, `pyca`, and several Rust NIF crates use
// for the same family of crashes.
//
// Restricted to Linux because Darwin/macOS already preserves loaded images by
// default in this scenario and the local test suite runs cleanly there.

fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("linux") {
        println!("cargo:rustc-link-arg-cdylib=-Wl,-z,nodelete");
    }
}
