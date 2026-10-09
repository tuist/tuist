//! Routing domains are verified by the deployment, never inferred from a
//! provider name, region name, or an RFC1918 pod address.

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
pub struct PeerTopology {
    pub provider: String,
    #[serde(default)]
    pub private_network: Option<String>,
    #[serde(default)]
    pub private_url: Option<String>,
    /// Exact same-provider domains approved for canonical mTLS. Approval must
    /// be reciprocal and never overrides the same-domain private-only path.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub canonical_networks: Vec<String>,
}

impl PeerTopology {
    pub fn validate(&self) -> Result<(), String> {
        if self.provider.trim().is_empty() || self.provider != self.provider.trim() {
            return Err(
                "peer topology requires a nonempty provider without surrounding spaces".into(),
            );
        }
        match (&self.private_network, &self.private_url) {
            (Some(network), Some(url))
                if !network.trim().is_empty() && network == network.trim() =>
            {
                validate_endpoint(url)?;
            }
            _ => return Err("peer topology requires both private_network and private_url".into()),
        }
        if self.canonical_networks.len() > 32 {
            return Err("peer topology permits at most 32 canonical networks".into());
        }
        for (index, network) in self.canonical_networks.iter().enumerate() {
            if network.is_empty()
                || network != network.trim()
                || Some(network) == self.private_network.as_ref()
                || self.canonical_networks[..index].contains(network)
            {
                return Err(
                    "canonical networks must be distinct nonempty remote domain IDs".into(),
                );
            }
        }
        Ok(())
    }

    pub fn same_provider(&self, peer: &Self) -> bool {
        !self.provider.is_empty() && self.provider == peer.provider
    }

    pub fn same_private_network(&self, peer: &Self) -> bool {
        self.same_provider(peer)
            && self.private_network.is_some()
            && self.private_network == peer.private_network
    }
}

fn validate_endpoint(value: &str) -> Result<(), String> {
    let url = reqwest::Url::parse(value).map_err(|e| format!("invalid peer endpoint: {e}"))?;
    if url.scheme() != "https"
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
        || url.path() != "/"
    {
        return Err(
            "topology-aware peer endpoints must be HTTPS origins without credentials".into(),
        );
    }
    Ok(())
}

/// Missing local metadata is the compatibility mode. Once enabled, unknown
/// remote metadata remains usable over mTLS during a rolling upgrade; it never
/// earns private-path preference. Different same-provider domains require
/// reciprocal explicit approval; otherwise their metadata is fail-closed.
pub fn endpoint<'a>(
    own: Option<&PeerTopology>,
    peer: Option<&'a PeerTopology>,
    canonical: &'a str,
) -> Result<&'a str, String> {
    let Some(own) = own else { return Ok(canonical) };
    validate_endpoint(canonical)?;
    let Some(peer) = peer else {
        return Ok(canonical);
    };
    peer.validate()?;
    if !own.same_provider(peer) {
        return Ok(canonical);
    }
    if own.private_network.is_none() || own.private_network != peer.private_network {
        if own
            .private_network
            .as_ref()
            .is_some_and(|network| peer.canonical_networks.contains(network))
            && peer
                .private_network
                .as_ref()
                .is_some_and(|network| own.canonical_networks.contains(network))
        {
            return Ok(canonical);
        }
        return Err(format!(
            "private replication unavailable: provider {} has incompatible routing domains {:?} and {:?}",
            own.provider, own.private_network, peer.private_network
        ));
    }
    peer.private_url.as_deref().ok_or_else(|| {
        "private replication unavailable: same-provider peer has no private endpoint".into()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    pub(super) fn topology(provider: &str, network: &str) -> PeerTopology {
        PeerTopology {
            provider: provider.into(),
            private_network: Some(network.into()),
            private_url: Some("https://private.example:7443".into()),
            canonical_networks: Vec::new(),
        }
    }

    #[test]
    fn provider_alone_does_not_prove_private_reachability() {
        let ord = topology("vultr", "ord-vpc-1");
        let scl = topology("vultr", "scl-vpc-1");
        assert!(endpoint(Some(&ord), Some(&scl), "https://public.example:7443").is_err());
        assert_eq!(
            endpoint(Some(&ord), Some(&ord), "https://public.example:7443").unwrap(),
            "https://private.example:7443"
        );
    }

    #[test]
    fn cross_provider_and_legacy_peers_remain_available_over_tls() {
        let ovh = topology("ovh", "vrack-1");
        let vultr = topology("vultr", "ord-vpc-1");
        let url = "https://public.example:7443";
        assert_eq!(endpoint(Some(&ovh), Some(&vultr), url).unwrap(), url);
        assert_eq!(endpoint(Some(&ovh), None, url).unwrap(), url);
        assert!(endpoint(Some(&ovh), None, "http://public.example").is_err());
        assert_eq!(
            endpoint(None, None, "http://legacy").unwrap(),
            "http://legacy"
        );
    }

    #[test]
    fn regional_canonical_routing_requires_exact_reciprocal_approval() {
        let mut ord = topology("vultr", "ord-vpc-1");
        let mut scl = topology("vultr", "scl-vpc-1");
        let url = "https://public.example:7443";
        ord.canonical_networks.push("scl-vpc-1".into());
        assert!(endpoint(Some(&ord), Some(&scl), url).is_err());
        assert!(endpoint(Some(&scl), Some(&ord), url).is_err());
        scl.canonical_networks.push("ord-vpc-1".into());
        assert_eq!(endpoint(Some(&ord), Some(&scl), url).unwrap(), url);
        assert_eq!(endpoint(Some(&scl), Some(&ord), url).unwrap(), url);
        assert!(!ord.same_private_network(&scl));
        assert_eq!(
            endpoint(Some(&ord), Some(&ord), url).unwrap(),
            "https://private.example:7443"
        );
        let mut typo = scl.clone();
        typo.private_network = Some("scl-typo".into());
        assert!(endpoint(Some(&ord), Some(&typo), url).is_err());
        let old: PeerTopology = serde_json::from_str(r#"{"provider":"vultr","private_network":"scl-vpc-1","private_url":"https://private.example:7443"}"#).unwrap();
        assert!(endpoint(Some(&ord), Some(&old), url).is_err());
        assert!(endpoint(Some(&ord), None, url).is_ok());
        for networks in [
            vec![""],
            vec![" scl-vpc-1"],
            vec!["ord-vpc-1"],
            vec!["scl-vpc-1", "scl-vpc-1"],
        ] {
            ord.canonical_networks = networks.into_iter().map(String::from).collect();
            assert!(ord.validate().is_err());
        }
    }

    #[tokio::test]
    async fn approved_remote_vpc_is_not_a_preferred_private_donor() {
        let mut own = topology("vultr", "ord");
        own.canonical_networks.push("scl".into());
        let mut remote = topology("vultr", "scl");
        remote.canonical_networks.push("ord".into());
        let ctx =
            crate::test_support::test_context(|config| config.peer_topology = Some(own.clone()))
                .await;
        let canonical = "https://public.example:7443";
        ctx.state
            .apply_peer_views(vec![crate::sync::roles::PeerView {
                private_healthy: true,
                url: canonical.into(),
                region: "scl".into(),
                topology: Some(remote),
                serving: true,
                draining: false,
            }]);
        assert!(!ctx.state.prefers_peer(canonical));
        let request = ctx
            .state
            .peer_request(
                reqwest::Method::GET,
                canonical,
                &format!("{canonical}/_internal/backfill/bodies"),
            )
            .unwrap()
            .build()
            .unwrap();
        assert_eq!(
            request.url().as_str(),
            format!("{canonical}/_internal/backfill/bodies")
        );
    }

    #[test]
    fn incomplete_and_unsafe_metadata_is_rejected() {
        let provider_only: PeerTopology = serde_json::from_str(r#"{"provider":"ovh"}"#).unwrap();
        assert!(provider_only.validate().is_err());
        let mut peer = topology("ovh", "vrack-1");
        for url in [
            "http://private",
            "https://user:password@private",
            "https://private/path",
            "https://private?query",
        ] {
            peer.private_url = Some(url.into());
            assert!(peer.validate().is_err());
        }
        peer.private_url = None;
        assert!(peer.validate().is_err());
    }

    #[tokio::test]
    async fn every_peer_request_uses_private_origin_and_keeps_canonical_identity() {
        let own = topology("ovh", "vrack-1");
        let ctx = crate::test_support::test_context(|config| {
            config.peer_topology = Some(own.clone());
        })
        .await;
        let canonical = "https://public.example:7443";
        let view = crate::sync::roles::PeerView {
            private_healthy: true,
            url: canonical.into(),
            region: "remote".into(),
            topology: Some(own),
            serving: true,
            draining: false,
        };
        ctx.state.apply_peer_views(vec![view.clone()]);
        for path in [
            "/_internal/sync/forward?after=123",
            "/_internal/backfill/entries?order=asc",
            "/_internal/backfill/bodies",
            "/_internal/backfill/artifacts/key",
        ] {
            let request = ctx
                .state
                .peer_request(
                    reqwest::Method::GET,
                    canonical,
                    &format!("{canonical}{path}"),
                )
                .unwrap()
                .build()
                .unwrap();
            assert_eq!(
                request.url().as_str(),
                format!("https://private.example:7443{path}")
            );
        }
        assert_eq!(ctx.state.peer_views.load()[0].url, canonical);
        let mut remote = view;
        remote.topology.as_mut().unwrap().provider = "vultr".into();
        ctx.state.apply_peer_views(vec![remote]);
        let request = ctx
            .state
            .peer_request(
                reqwest::Method::GET,
                canonical,
                &format!("{canonical}/_internal/status"),
            )
            .unwrap()
            .build()
            .unwrap();
        assert_eq!(request.url().host_str(), Some("public.example"));
        ctx.state.apply_peer_views(vec![]);
        assert!(
            ctx.state
                .peer_request(
                    reqwest::Method::GET,
                    canonical,
                    &format!("{canonical}/_internal/status")
                )
                .is_err(),
            "membership removal must not race a public fallback"
        );
    }

    #[tokio::test]
    async fn unreachable_private_endpoint_never_retries_the_public_listener() {
        use std::sync::{
            Arc,
            atomic::{AtomicUsize, Ordering},
        };
        let hits = Arc::new(AtomicUsize::new(0));
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let count = hits.clone();
        let server = tokio::spawn(async move {
            loop {
                let (stream, _) = listener.accept().await.unwrap();
                count.fetch_add(1, Ordering::Relaxed);
                drop(stream);
            }
        });
        let private = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let private_address = private.local_addr().unwrap();
        drop(private);
        let mut own = topology("ovh", "vrack-1");
        own.private_url = Some(format!("https://{private_address}"));
        let ctx =
            crate::test_support::test_context(|config| config.peer_topology = Some(own.clone()))
                .await;
        // The advertised public endpoint is syntactically HTTPS; the listener
        // counts accepted TCP connections as well as HTTP so even a TLS retry
        // cannot be mistaken for no fallback.
        let canonical = format!("https://{address}");
        ctx.state
            .apply_peer_views(vec![crate::sync::roles::PeerView {
                private_healthy: true,
                url: canonical.clone(),
                region: "remote".into(),
                topology: Some(own),
                serving: true,
                draining: false,
            }]);
        assert!(
            ctx.state
                .peer_request(reqwest::Method::GET, &canonical, &format!("{canonical}/"))
                .unwrap()
                .send()
                .await
                .is_err()
        );
        assert_eq!(hits.load(Ordering::Relaxed), 0);
        server.abort();
    }
}
