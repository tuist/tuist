// Linker tweaks for the cdylib.
//
// On Linux, link the cdylib with `-Wl,-z,nodelete` so that `dlclose` does not
// unmap our shared object. Several transitive C dependencies pulled in
// through bashkit (and its async I/O stack) register `atexit` handlers at
// library load. If BEAM `dlclose`s the NIF during shutdown, those handlers
// still sit in libc's exit-handler table and point into the now-unmapped
// region the `.so` occupied. When libc later runs `__run_exit_handlers` it
// jumps to a freed page and the process segfaults just before exit.
//
// This is the same family of teardown segfaults documented on
// `Condukt.Bashkit.NIF` (and previously observed on
// `Condukt.Microsandbox.NIF` with the matching workaround). `-z nodelete`
// tells the dynamic linker that the object is not eligible to be unloaded,
// so `dlclose` becomes a no-op for it. The `.so` stays mapped until process
// exit, atexit handlers remain callable, and libc unwinds cleanly.
//
// Restricted to Linux because Darwin/macOS already preserves loaded images by
// default in this scenario and the local test suite runs cleanly there.

fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("linux") {
        println!("cargo:rustc-link-arg-cdylib=-Wl,-z,nodelete");
    }
}
