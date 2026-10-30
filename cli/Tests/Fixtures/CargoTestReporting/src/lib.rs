/// A normal doctest.
/// ```
/// assert_eq!(tuist_cargo_reporting_fixture::answer(), 42);
/// ```
///
/// A compile-fail doctest.
/// ```compile_fail
/// let answer: bool = 42;
/// ```
///
/// An expected panic.
/// ```should_panic
/// panic!("expected");
/// ```
///
/// An ignored doctest.
/// ```ignore
/// assert!(false);
/// ```
///
/// A compile-only doctest.
/// ```no_run
/// assert_eq!(tuist_cargo_reporting_fixture::answer(), 42);
/// ```
pub fn answer() -> u32 {
    42
}

#[cfg(test)]
mod tests {
    #[test]
    fn passes() {
        assert_eq!(super::answer(), 42);
        if let Some(path) = std::env::var_os("TUIST_FIXTURE_LEAK_PID") {
            let child = if std::env::var_os("TUIST_FIXTURE_TICK").is_some() {
                std::process::Command::new("/bin/sh")
                    .args(["-c", "while :; do printf tick >&2; /bin/sleep 0.05; done"])
                    .spawn()
                    .unwrap()
            } else {
                std::process::Command::new("/bin/sleep")
                    .arg("30")
                    .spawn()
                    .unwrap()
            };
            std::fs::write(path, child.id().to_string()).unwrap();
        }
    }

    #[test]
    #[ignore = "not enabled by default"]
    fn ignored() {
        panic!("ignored");
    }

    #[test]
    fn optionally_fails() {
        if std::env::var_os("TUIST_FIXTURE_NOISY").is_some() {
            for index in 0..1500 {
                println!("captured line {index:04}: {}", "x".repeat(50));
            }
        }
        assert!(std::env::var_os("TUIST_FIXTURE_FAIL").is_none());
    }
}
