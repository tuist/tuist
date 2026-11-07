//! `condukt-egress proxy` subcommand.
//!
//! Transparent egress proxy with per-session CA-based TLS termination
//! (HTTPS) and head-capture forwarding (cleartext HTTP). A CA cert and
//! key path are required; without them the proxy refuses to start
//! because there is no useful audit it can perform on TLS without
//! terminating it.

use clap::Args as ClapArgs;
use std::error::Error;
use std::sync::Arc;
use tokio::net::TcpListener;

mod conn;
mod control;
mod event;
mod h2;
mod http1;
mod orig_dst;
mod policy;
mod sni;
mod tls;

#[derive(ClapArgs, Debug)]
pub struct Args {
    /// Address to listen on for redirected traffic from the workspace.
    /// Defaults to the proxy port netfilter-setup targets.
    #[arg(long, env = "CONDUKT_EGRESS_LISTEN", default_value = "0.0.0.0:15001")]
    pub listen: String,

    /// Address to listen on for the BEAM-side control channel client.
    /// The BEAM reaches this via the Kubernetes port-forward API.
    #[arg(
        long,
        env = "CONDUKT_EGRESS_CONTROL_LISTEN",
        default_value = "0.0.0.0:15002"
    )]
    pub control_listen: String,

    /// Path to the session's egress policy JSON file. Mirrors the BEAM
    /// `Condukt.Sandbox.NetworkPolicy` struct (snake-cased keys).
    #[arg(
        long,
        env = "CONDUKT_EGRESS_POLICY_FILE",
        default_value = "/etc/condukt/policy.json"
    )]
    pub policy_file: String,

    /// Path to the per-session CA certificate, in PEM. Required.
    #[arg(long, env = "CONDUKT_EGRESS_CA_CERT")]
    pub ca_cert_path: String,

    /// Path to the per-session CA private key, in PEM. Required.
    #[arg(long, env = "CONDUKT_EGRESS_CA_KEY")]
    pub ca_key_path: String,

    /// Session id passed through on every emitted event.
    #[arg(long, env = "CONDUKT_EGRESS_SESSION_ID")]
    pub session_id: Option<String>,
}

pub fn run(args: Args) -> Result<(), Box<dyn Error>> {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;
    runtime.block_on(run_async(args))
}

async fn run_async(args: Args) -> Result<(), Box<dyn Error>> {
    let policy_json = tokio::fs::read_to_string(&args.policy_file)
        .await
        .map_err(|e| format!("reading policy {}: {}", args.policy_file, e))?;
    let policy: policy::Policy = serde_json::from_str(&policy_json)
        .map_err(|e| format!("parsing policy {}: {}", args.policy_file, e))?;
    let policy = Arc::new(policy);

    let ca = Arc::new(tls::CaContext::load(&args.ca_cert_path, &args.ca_key_path).await?);

    eprintln!(
        "condukt-egress proxy: listen={} control={} policy={} ca={}",
        args.listen, args.control_listen, args.policy_file, args.ca_cert_path
    );

    let control = Arc::new(control::ControlChannel::start(&args.control_listen).await?);

    let listener = TcpListener::bind(&args.listen).await?;
    eprintln!("condukt-egress proxy: accepting connections");

    loop {
        let (client, _peer) = match listener.accept().await {
            Ok(pair) => pair,
            Err(err) => {
                eprintln!("condukt-egress proxy: accept failed: {err}");
                continue;
            }
        };

        let policy = Arc::clone(&policy);
        let control = Arc::clone(&control);
        let ca = Arc::clone(&ca);
        let session_id = args.session_id.clone();

        tokio::spawn(async move {
            conn::handle(client, policy, control, ca, session_id).await;
        });
    }
}
