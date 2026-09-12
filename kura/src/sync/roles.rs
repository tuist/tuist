//! Who pulls from whom (design §2).
//!
//! Pure: takes the membership view (what every peer's `/_internal/status`
//! answered) plus whatever roles the control plane published, and returns
//! the links this node opens. The same function runs on every node of a
//! mesh, so as long as views agree the roles agree; the serverless
//! self-hosted mode (§2.4) is just the case with nothing published.
//!
//! Every present peer is pulled from. A peer that cannot serve the feed or
//! the ascending listing — a release that predates pull — still gets a
//! link, which settles as abandoned once its bootstrap budget is spent and
//! keeps retrying quietly; whatever that peer writes reaches this node
//! through the push receivers kept for it (`http.rs`, `/_internal/replicate/*`).

use std::collections::BTreeMap;

/// One peer as the membership loop last saw it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PeerView {
    pub url: String,
    pub region: String,
    /// `serving` in the peer's traffic state.
    pub serving: bool,
    pub draining: bool,
}

/// A role the control plane published (`peer_roles` beside `peers`).
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct PublishedRole {
    pub url: String,
    pub region: String,
    pub gateway: bool,
}

/// The links this node opens.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Roles {
    /// This node pulls cross-region.
    pub own_gateway: bool,
    /// Same-region peers this node reads the arrival feed of.
    pub siblings: Vec<String>,
    /// `(url, region)` of every remote region's gateway(s) this node reads,
    /// empty unless `own_gateway`.
    pub remote_gateways: Vec<(String, String)>,
}

pub struct RoleInputs<'a> {
    pub own_url: &'a str,
    pub own_region: &'a str,
    pub own_serving: bool,
    pub own_draining: bool,
    pub peers: &'a [PeerView],
    pub published: &'a [PublishedRole],
}

/// Gateway of one region: the published gateways that are present in the
/// view, else the best candidate by (serving and not draining, not
/// draining, any) then lowest URL.
fn region_gateways(
    candidates: &[&PeerView],
    published: &[PublishedRole],
    region: &str,
) -> Vec<String> {
    let published_present: Vec<String> = published
        .iter()
        .filter(|role| role.gateway && role.region == region)
        .filter(|role| candidates.iter().any(|peer| peer.url == role.url))
        .map(|role| role.url.clone())
        .collect();
    if !published_present.is_empty() {
        return published_present;
    }
    let rank = |peer: &PeerView| match (peer.serving && !peer.draining, !peer.draining) {
        (true, _) => 0,
        (false, true) => 1,
        (false, false) => 2,
    };
    candidates
        .iter()
        .min_by(|a, b| rank(a).cmp(&rank(b)).then_with(|| a.url.cmp(&b.url)))
        .map(|peer| vec![peer.url.clone()])
        .unwrap_or_default()
}

pub fn derive_roles(inputs: &RoleInputs<'_>) -> Roles {
    let mut siblings: Vec<String> = inputs
        .peers
        .iter()
        .filter(|peer| peer.region == inputs.own_region)
        .map(|peer| peer.url.clone())
        .collect();
    siblings.sort();
    let mut roles = Roles {
        siblings,
        ..Roles::default()
    };

    let own = PeerView {
        url: inputs.own_url.to_owned(),
        region: inputs.own_region.to_owned(),
        serving: inputs.own_serving,
        draining: inputs.own_draining,
    };
    let mut by_region: BTreeMap<&str, Vec<&PeerView>> = BTreeMap::new();
    by_region.entry(inputs.own_region).or_default().push(&own);
    for peer in inputs.peers.iter() {
        by_region
            .entry(peer.region.as_str())
            .or_default()
            .push(peer);
    }

    let own_gateways = region_gateways(
        &by_region[inputs.own_region],
        inputs.published,
        inputs.own_region,
    );
    roles.own_gateway = own_gateways.iter().any(|url| url == inputs.own_url);
    if roles.own_gateway {
        for (region, candidates) in &by_region {
            if *region == inputs.own_region {
                continue;
            }
            for url in region_gateways(candidates, inputs.published, region) {
                roles.remote_gateways.push((url, (*region).to_owned()));
            }
        }
        roles.remote_gateways.sort();
    }
    roles
}

#[cfg(test)]
mod tests {
    use super::*;

    fn peer(url: &str, region: &str, serving: bool, draining: bool) -> PeerView {
        PeerView {
            url: url.into(),
            region: region.into(),
            serving,
            draining,
        }
    }

    fn inputs<'a>(
        own_url: &'a str,
        own_region: &'a str,
        peers: &'a [PeerView],
        published: &'a [PublishedRole],
    ) -> RoleInputs<'a> {
        RoleInputs {
            own_url,
            own_region,
            own_serving: true,
            own_draining: false,
            peers,
            published,
        }
    }

    // A-16: lowest URL per region among serving, non-draining peers.
    #[test]
    fn serverless_rule_picks_the_lowest_serving_url_per_region() {
        let peers = [
            peer("https://b.us", "us", true, false),
            peer("https://a.eu", "eu", true, false),
            peer("https://b.eu", "eu", true, false),
            peer("https://a.ap", "ap", true, false),
        ];
        let roles = derive_roles(&inputs("https://a.us", "us", &peers, &[]));
        assert!(roles.own_gateway, "a.us is the lowest url of us");
        assert_eq!(roles.siblings, vec!["https://b.us"]);
        assert_eq!(
            roles.remote_gateways,
            vec![
                ("https://a.ap".to_string(), "ap".to_string()),
                ("https://a.eu".to_string(), "eu".to_string())
            ],
            "every remote region's gateway is pulled from, a region of one included"
        );

        let peers = [
            peer("https://a.us", "us", true, false),
            peer("https://a.eu", "eu", true, false),
            peer("https://b.eu", "eu", true, false),
            peer("https://a.ap", "ap", true, false),
        ];
        let roles = derive_roles(&inputs("https://b.us", "us", &peers, &[]));
        assert!(!roles.own_gateway);
        assert!(
            roles.remote_gateways.is_empty(),
            "non-gateways open no cross-region link"
        );
        assert_eq!(roles.siblings, vec!["https://a.us"]);
    }

    #[test]
    fn a_draining_or_joining_sibling_does_not_take_the_role() {
        let peers = [peer("https://a.us", "us", true, true)];
        let roles = derive_roles(&inputs("https://b.us", "us", &peers, &[]));
        assert!(roles.own_gateway, "the draining lower url is skipped");
        assert_eq!(
            roles.siblings,
            vec!["https://a.us"],
            "but it is still pulled from"
        );

        let peers = [peer("https://a.us", "us", false, false)];
        let roles = derive_roles(&inputs("https://b.us", "us", &peers, &[]));
        assert!(
            roles.own_gateway,
            "a joining sibling yields to a serving one"
        );
    }

    #[test]
    fn a_region_of_one_is_always_its_own_gateway_even_while_joining() {
        let peers = [peer("https://a.eu", "eu", true, false)];
        let roles = derive_roles(&RoleInputs {
            own_serving: false,
            ..inputs("https://a.us", "us", &peers, &[])
        });
        assert!(roles.own_gateway);
        assert_eq!(roles.remote_gateways.len(), 1);
    }

    // A-17: a published role overrides the local rule.
    #[test]
    fn published_roles_override_the_local_rule_when_present_in_the_view() {
        let peers = [
            peer("https://b.us", "us", true, false),
            peer("https://a.eu", "eu", true, false),
            peer("https://b.eu", "eu", true, false),
        ];
        let published = [
            PublishedRole {
                url: "https://b.us".into(),
                region: "us".into(),
                gateway: true,
            },
            PublishedRole {
                url: "https://a.us".into(),
                region: "us".into(),
                gateway: false,
            },
            PublishedRole {
                url: "https://b.eu".into(),
                region: "eu".into(),
                gateway: true,
            },
        ];
        let roles = derive_roles(&inputs("https://a.us", "us", &peers, &published));
        assert!(
            !roles.own_gateway,
            "the control plane made b.us the gateway"
        );
        let roles = derive_roles(&inputs("https://b.us", "us", &peers, &published));
        assert!(roles.own_gateway);
        assert_eq!(
            roles.remote_gateways,
            vec![("https://b.eu".to_string(), "eu".to_string())]
        );

        // A published gateway that is not in the view falls back to the
        // local rule — overlap over a gap.
        let published = [PublishedRole {
            url: "https://c.us".into(),
            region: "us".into(),
            gateway: true,
        }];
        let roles = derive_roles(&inputs("https://a.us", "us", &peers, &published));
        assert!(roles.own_gateway);
    }

    #[test]
    fn a_node_with_no_peers_is_its_own_gateway_with_no_links() {
        let roles = derive_roles(&inputs("https://a.us", "us", &[], &[]));
        assert_eq!(
            roles,
            Roles {
                own_gateway: true,
                siblings: vec![],
                remote_gateways: vec![],
            }
        );
    }
}
