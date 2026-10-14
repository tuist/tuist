use super::request_agent;
use tuist_cargo_cache_core::{AgentRequest, AgentResponse};

/// Write to stderr without failing the build when the pipe is closed.
pub(crate) fn note(message: &str) {
    crate::logging::note(message);
}

/// Whether this process's stderr belongs to the compiler it stands in for.
///
/// Set once at cc- or rustc-shim entry. Build scripts read an intercepted
/// compiler's stderr as part of its answer: cc-rs marks a probed flag unsupported
/// the moment anything lands there. Cargo also saves rustc stderr in its
/// fingerprints and replays it even when no compiler runs. Shim diagnostics
/// must therefore travel through the live session instead.
static STDERR_RESERVED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Declare that this process replays compiler output on stderr and must not
/// mix its own diagnostics into it.
pub(crate) fn reserve_stderr_for_compiler() {
    STDERR_RESERVED.store(true, std::sync::atomic::Ordering::Relaxed);
}

/// Report a shim diagnostic without polluting a reserved stderr.
///
/// Delivered to the session's agent, which prints it from the process that
/// owns the build. When the agent cannot take it, the message falls back to
/// this process's stderr only where that stream is not the compiler's --
/// losing a diagnostic costs a little visibility, while poisoning a configure
/// probe costs the build its cache keys.
pub(crate) fn report_shim_warning(message: &str) {
    report_shim_diagnostic(Severity::Warning, message);
}

/// Report a fatal shim diagnostic without losing it when transport fails.
///
/// The session retains the error's severity when it displays and emits it.
/// The local fallback keeps the fatal reason visible when delivery fails,
/// including when an older agent does not understand the error request.
pub(crate) fn report_shim_error(message: &str) {
    report_shim_diagnostic(Severity::Error, message);
}

#[derive(Clone, Copy)]
enum Severity {
    Warning,
    Error,
}

fn report_shim_diagnostic(severity: Severity, message: &str) {
    let message = diagnostic_message(message);
    let (label, request) = match severity {
        Severity::Warning => (
            "warning",
            AgentRequest::RecordWarning {
                message: message.clone(),
            },
        ),
        Severity::Error => (
            "error",
            AgentRequest::RecordError {
                message: message.clone(),
            },
        ),
    };
    let response = request_agent(&[request])
        .ok()
        .and_then(|responses| responses.into_iter().next());
    let delivered = matches!(
        (severity, response),
        (Severity::Warning, Some(AgentResponse::WarningRecorded))
            | (Severity::Error, Some(AgentResponse::ErrorRecorded))
    );
    if !delivered
        && (matches!(severity, Severity::Error)
            || !STDERR_RESERVED.load(std::sync::atomic::Ordering::Relaxed))
    {
        note(&format!("tuist_cargo_cache[{label}]: {message}"));
    }
}

/// Keep forwarded diagnostics single-line and below the agent's byte limit.
pub(super) fn diagnostic_message(message: &str) -> String {
    let mut message = message.replace(['\n', '\r', '\0'], "; ");
    if message.len() > 2048 {
        let end = (0..=2048).rfind(|&index| message.is_char_boundary(index));
        message.truncate(end.unwrap_or_default());
        message.push_str("...");
    }
    message
}
