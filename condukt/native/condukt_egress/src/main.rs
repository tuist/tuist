//! `condukt-egress` is the sidecar binary backing the egress audit and
//! policy layer for `Condukt.Sandbox.Kubernetes`.
//!
//! It ships as a single static binary with two operating modes selected by
//! subcommand:
//!
//! - `netfilter-setup` runs as a Kubernetes init container. It writes the
//!   iptables rules that redirect outbound TCP 80/443 traffic from the
//!   workspace container into the sidecar's transparent proxy on
//!   localhost:15001, exempting the sidecar's own uid so the proxy can
//!   reach the internet. Requires `CAP_NET_ADMIN`. Exits when done.
//!
//! - `proxy` runs as a long-lived sidecar container. It listens on
//!   localhost:15001, recovers the original destination via
//!   `SO_ORIGINAL_DST`, peeks the TLS ClientHello for SNI, evaluates the
//!   per-session policy, and either splices bytes through unmodified
//!   (transparent passthrough) or terminates TLS with a per-session
//!   CA-signed leaf to capture method/path/headers/body. It also listens
//!   on a control TCP port carrying the NDJSON event + decision channel;
//!   the BEAM reaches that port directly via `pods/portforward`, so no
//!   stdin/stdout bridge subcommand is needed.
//!
//! The two modes share the same image so K8s pulls one artifact for both
//! the init and sidecar containers. The pod spec selects the mode via
//! `command:`. Every option on each subcommand is also readable from a
//! `CONDUKT_EGRESS_*` environment variable (see `--help` on each
//! subcommand), which is how the K8s pod spec injects configuration.

use clap::{Parser, Subcommand};

mod netfilter;
mod proxy;

/// Egress sidecar for Condukt's network policy layer.
///
/// Run one of the two subcommands. Each subcommand's flags also bind to
/// `CONDUKT_EGRESS_*` environment variables; run `condukt-egress <mode>
/// --help` for the full per-mode option list and their env-var names.
#[derive(Parser, Debug)]
#[command(name = "condukt-egress", version, about, long_about = None)]
struct Cli {
    /// Which operating mode to run. The Kubernetes pod spec selects this
    /// per container: `netfilter-setup` for the init container, `proxy`
    /// for the long-lived sidecar.
    #[command(subcommand)]
    mode: Mode,
}

#[derive(Subcommand, Debug)]
enum Mode {
    /// Configure iptables NAT rules to redirect outbound TCP 80/443 to the
    /// sidecar proxy. Designed to run as a Kubernetes init container with
    /// CAP_NET_ADMIN. Exits after the rules are in place. Options:
    /// `--proxy-port`, `--sidecar-uid`, `--iptables-bin`.
    NetfilterSetup(netfilter::Args),

    /// Run the transparent egress proxy. Long-lived sidecar mode.
    /// Listens for redirected workspace traffic plus the BEAM control
    /// channel. Options: `--listen`, `--control-listen`, `--policy-file`,
    /// `--ca-cert-path`, `--ca-key-path`, `--session-id`.
    Proxy(proxy::Args),
}

fn main() -> std::process::ExitCode {
    let cli = Cli::parse();
    let result = match cli.mode {
        Mode::NetfilterSetup(args) => netfilter::run(args),
        Mode::Proxy(args) => proxy::run(args),
    };

    match result {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("condukt-egress: {err:#}");
            std::process::ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn netfilter_setup_parses_with_defaults() {
        let cli = Cli::try_parse_from(["condukt-egress", "netfilter-setup"]).unwrap();
        match cli.mode {
            Mode::NetfilterSetup(args) => {
                assert_eq!(args.proxy_port, 15_001);
                assert_eq!(args.sidecar_uid, 1337);
                assert_eq!(args.iptables_bin, "iptables");
            }
            other => panic!("expected NetfilterSetup, got {other:?}"),
        }
    }

    #[test]
    fn proxy_requires_the_ca_paths() {
        // Both CA paths are mandatory; omitting them is a parse error,
        // not a panic at runtime.
        assert!(Cli::try_parse_from(["condukt-egress", "proxy"]).is_err());

        let cli = Cli::try_parse_from([
            "condukt-egress",
            "proxy",
            "--ca-cert-path",
            "/etc/condukt/ca.pem",
            "--ca-key-path",
            "/etc/condukt/ca.key",
        ])
        .unwrap();

        match cli.mode {
            Mode::Proxy(args) => {
                assert_eq!(args.ca_cert_path, "/etc/condukt/ca.pem");
                assert_eq!(args.ca_key_path, "/etc/condukt/ca.key");
                assert_eq!(args.listen, "0.0.0.0:15001");
                assert_eq!(args.control_listen, "0.0.0.0:15002");
                assert_eq!(args.policy_file, "/etc/condukt/policy.json");
                assert!(args.session_id.is_none());
            }
            other => panic!("expected Proxy, got {other:?}"),
        }
    }

    #[test]
    fn unknown_subcommand_is_rejected() {
        assert!(Cli::try_parse_from(["condukt-egress", "wat"]).is_err());
    }

    #[test]
    fn proxy_flags_override_defaults() {
        let cli = Cli::try_parse_from([
            "condukt-egress",
            "proxy",
            "--ca-cert-path",
            "/c",
            "--ca-key-path",
            "/k",
            "--listen",
            "127.0.0.1:1",
            "--session-id",
            "sess-9",
        ])
        .unwrap();

        match cli.mode {
            Mode::Proxy(args) => {
                assert_eq!(args.listen, "127.0.0.1:1");
                assert_eq!(args.session_id.as_deref(), Some("sess-9"));
            }
            other => panic!("expected Proxy, got {other:?}"),
        }
    }
}
