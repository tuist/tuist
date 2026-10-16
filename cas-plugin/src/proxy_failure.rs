//! What surfaces a failing proxy outside `TUIST_CAS_LOG`.
//!
//! A failed proxy request degrades to a miss, which is also what a cold cache answers,
//! so a build that never reached the proxy looks exactly like one that found nothing.
//! The build service reports it instead: its first failed cross-machine lookup returns a
//! cache error carrying [`message`], and swift-build turns that into a non-fatal
//! `warning: CAS error: ...` on the cache key query task. Nowhere else is an error safe:
//! from a local-only lookup it fails the materialize task, and from `clang -cc1`'s own
//! cross-machine lookup it fails the compilation, so compilers and every other lookup
//! keep answering with a miss.
//!
//! One warning per build. The build service opens its lookup handles for a build,
//! disposes them when the build ends, and looks up through more than one of them at
//! once, so the first handle to report holds the claim until it is disposed. A request
//! the proxy answers releases it too, since a later failure is a new outage.

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::OnceLock;

use crate::proxy_proto::STORE_STALL_ERROR;

static CLAIM: ReportClaim = ReportClaim::new();

/// Whether this failed lookup is the one that reports the failure, claiming the report
/// for `handle` when it is.
pub fn should_report(globally: bool, handle: usize) -> bool {
    globally && running_in_build_service() && CLAIM.claim(handle)
}

pub fn handle_disposed(handle: usize) {
    CLAIM.release_if_held_by(handle);
}

pub fn proxy_answered() {
    CLAIM.release();
}

/// The warning's text, which swift-build prefixes with `CAS error: `. A proxy
/// that answers but cannot use the store is running, so its advice is about the
/// store access it is waiting on, not about starting the proxy.
pub fn message(socket_path: &str, error: &str) -> String {
    let advice = if error.contains(STORE_STALL_ERROR) {
        "Give tuist-cas-proxy access to that directory (System Settings > Privacy & Security > \
         Full Disk Access), or check endpoint-security software on this Mac."
    } else {
        "Run `tuist setup cache` if the proxy is not running."
    };
    format!(
        "The Tuist Xcode cache proxy at {socket_path} failed ({error}). Compilations that \
         needed it used the local cache only, without remote cache hits. Their uploads are \
         kept on disk and sent once the proxy is reachable again. {advice}"
    )
}

/// The lookup handle holding the report, or none. A handle is its state's address, which
/// is never zero.
struct ReportClaim {
    held_by: AtomicUsize,
}

impl ReportClaim {
    const fn new() -> Self {
        Self {
            held_by: AtomicUsize::new(0),
        }
    }

    fn claim(&self, handle: usize) -> bool {
        self.held_by
            .compare_exchange(0, handle, Ordering::SeqCst, Ordering::SeqCst)
            .is_ok()
    }

    fn release_if_held_by(&self, handle: usize) {
        let _ = self
            .held_by
            .compare_exchange(handle, 0, Ordering::SeqCst, Ordering::SeqCst);
    }

    fn release(&self) {
        if self.held_by.load(Ordering::Relaxed) != 0 {
            self.held_by.store(0, Ordering::SeqCst);
        }
    }
}

fn running_in_build_service() -> bool {
    static IN_BUILD_SERVICE: OnceLock<bool> = OnceLock::new();
    *IN_BUILD_SERVICE.get_or_init(|| {
        std::env::current_exe()
            .ok()
            .and_then(|executable| {
                executable
                    .file_name()
                    .map(|name| is_build_service(&name.to_string_lossy()))
            })
            .unwrap_or(false)
    })
}

fn is_build_service(executable_name: &str) -> bool {
    matches!(executable_name, "SWBBuildService" | "XCBBuildService")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_first_handle_to_report_holds_the_claim_until_it_is_disposed() {
        let claim = ReportClaim::new();

        assert!(claim.claim(0x10));
        assert!(
            !claim.claim(0x20),
            "a second handle of the same build stays quiet"
        );
        claim.release_if_held_by(0x20);
        assert!(
            !claim.claim(0x20),
            "disposing a handle that did not report keeps the claim"
        );
        claim.release_if_held_by(0x10);
        assert!(claim.claim(0x30), "the next build's handle reports again");
    }

    #[test]
    fn a_proxy_that_answers_releases_the_claim() {
        let claim = ReportClaim::new();

        assert!(claim.claim(0x10));
        claim.release();
        assert!(claim.claim(0x10));
    }

    #[test]
    fn only_the_build_service_reports() {
        assert!(is_build_service("SWBBuildService"));
        assert!(is_build_service("XCBBuildService"));
        assert!(!is_build_service("swift-frontend"));
        assert!(!is_build_service("clang"));
    }

    #[test]
    fn the_message_names_the_socket_and_the_failure_on_one_line() {
        let message = message(
            "/Users/me/.local/state/tuist/cas-proxy.sock",
            "proxy connect: refused",
        );
        assert!(message.contains("/Users/me/.local/state/tuist/cas-proxy.sock"));
        assert!(message.contains("proxy connect: refused"));
        assert!(!message.contains('\n'));
    }

    #[test]
    fn a_stalled_store_is_explained_instead_of_suggesting_setup() {
        let message = message(
            "/Users/me/.local/state/tuist/cas-proxy.sock",
            &format!("proxy error: {STORE_STALL_ERROR}: opening the store at /dd/plugin has not returned after 12s"),
        );
        assert!(message.contains("opening the store at /dd/plugin"));
        assert!(message.contains("Full Disk Access"));
        assert!(!message.contains("tuist setup cache"), "the proxy is running");
        assert!(!message.contains('\n'));
    }
}
