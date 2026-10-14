use std::process::ExitCode;

fn main() -> ExitCode {
    if let Some(code) = tuist_cargo_cache::supervision::dispatch() {
        return code;
    }
    if let Some(code) = tuist_cargo_cache::cli::launch::dispatch() {
        return code;
    }
    if let Some(code) = tuist_cargo_cache::cli::test_runner::dispatch() {
        return code;
    }
    tuist_cargo_cache::phase_timing::initialize();
    if tuist_cargo_cache::session::is_build_script_shim() {
        return tuist_cargo_cache::session::run_build_script_shim();
    }
    // Cargo invokes the rustc shim thousands of times per build. Dispatch on
    // argv0 before any runtime, logging, or configuration setup.
    if tuist_cargo_cache::session::is_rustc_shim() {
        return tuist_cargo_cache::session::run_rustc_shim();
    }
    if tuist_cargo_cache::session::is_rustdoc_shim() {
        return tuist_cargo_cache::session::run_rustdoc_shim();
    }
    if let Some(code) = tuist_cargo_cache::session::cmake::dispatch() {
        return code;
    }
    if let Some(language) = tuist_cargo_cache::session::is_cc_shim() {
        return tuist_cargo_cache::session::run_cc_shim(language);
    }

    match tuist_cargo_cache::cli::launch::recover_cli() {
        Ok(Some(code)) => return code,
        Ok(None) => {}
        Err(error) => {
            eprintln!("tuist_cargo_cache[error]: failed to recover build environment: {error:#}");
            return ExitCode::FAILURE;
        }
    }
    tuist_cargo_cache::cli::launch::remember_caller();
    let cargo_shim = tuist_cargo_cache::cli::is_cargo_shim();

    // Top-level help and version terminate during argument parsing. Avoid
    // constructing the logger for those read-only paths: it cannot emit
    // anything before the parser exits, so the setup is unnecessary work.
    if cargo_shim
        || !matches!(
            std::env::args_os().nth(1).as_deref(),
            Some(arg) if arg == "--help" || arg == "-h" || arg == "--version" || arg == "-V"
        )
    {
        tuist_cargo_cache::logging::init();
    }

    if cargo_shim {
        return match tuist_cargo_cache::cli::run_cargo_shim() {
            Ok(code) => code,
            Err(error) => {
                eprintln!("tuist_cargo_cache[error]: {error:#}");
                ExitCode::FAILURE
            }
        };
    }

    match tuist_cargo_cache::cli::run() {
        Ok(code) => code,
        Err(error) => {
            eprintln!("tuist_cargo_cache[error]: {error:#}");
            ExitCode::FAILURE
        }
    }
}
