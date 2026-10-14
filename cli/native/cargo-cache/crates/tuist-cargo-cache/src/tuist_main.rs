//! Invocation-local Tuist runtime. There is deliberately no upstream CLI parser.
use std::process::ExitCode;

struct PublicReportGuard;
impl Drop for PublicReportGuard {
    fn drop(&mut self) {
        tuist_cargo_cache_core::flush_public_cache_report();
    }
}

fn main() -> ExitCode {
    let _report = PublicReportGuard;
    if let Some(code) = tuist_cargo_cache::supervision::dispatch() {
        return code;
    }
    if let Some(code) = tuist_cargo_cache::cli::launch::dispatch() {
        return code;
    }
    if let Some(code) = tuist_cargo_cache::cli::test_runner::dispatch() {
        return code;
    }
    if std::env::args().skip(1).eq(["__tuist_gc_automatic"]) {
        return match tuist_cargo_cache::cli::run_tuist_gc() {
            Ok(code) => code,
            Err(error) => {
                eprintln!("Tuist Cargo cache cleanup: {error:#}");
                ExitCode::FAILURE
            }
        };
    }
    tuist_cargo_cache::phase_timing::initialize();
    if tuist_cargo_cache::session::is_build_script_shim() {
        return tuist_cargo_cache::session::run_build_script_shim();
    }
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
    if std::env::args().skip(1).eq(["__tuist_protocol"]) {
        println!("tuist-cargo-cache 1");
        return ExitCode::SUCCESS;
    }
    match tuist_cargo_cache::cli::launch::recover_cli() {
        Ok(Some(code)) => return code,
        Ok(None) => (),
        Err(error) => {
            eprintln!("Tuist Cargo cache: {error:#}");
            return ExitCode::FAILURE;
        }
    }
    tuist_cargo_cache::cli::launch::remember_caller();
    tuist_cargo_cache::logging::init();
    match tuist_cargo_cache::cli::run_tuist_cargo() {
        Ok(code) => code,
        Err(error) => {
            eprintln!("Tuist Cargo cache: {error:#}");
            ExitCode::FAILURE
        }
    }
}
