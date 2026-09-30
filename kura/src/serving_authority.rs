//! Managed serving grants. Expiry is admission/commit defence, not proof that a
//! suspended process has stopped. Replacement requires positive external fencing.
use serde::{Deserialize, Serialize};
use std::{
    future::Future,
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct Holder {
    pub instance_uid: String,
    pub pod_uid: String,
    pub incarnation: String,
    pub host: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Grant {
    pub epoch: u64,
    pub holder: Holder,
    pub expires_ms: u64,
    pub phase: String,
    #[serde(default)]
    pub handover: Option<crate::handover::Intent>,
    #[serde(default)]
    pub barrier: Option<crate::handover::Receipt>,
}

struct Active {
    grant: Grant,
    deadline: Instant,
}

pub struct ServingAuthority {
    identity: Holder,
    enabled: bool,
    active: Mutex<Option<Active>>,
    observed: Mutex<Option<Grant>>,
    mutations: AtomicUsize,
    pub barrier: Mutex<Option<crate::handover::Receipt>>,
    marker: Option<std::path::PathBuf>,
    revoked_epoch: std::sync::atomic::AtomicU64,
    store: Mutex<Option<Arc<crate::store::Store>>>,
}

#[derive(Clone)]
pub struct Permit(Arc<PermitInner>);
struct PermitInner {
    authority: Arc<ServingAuthority>,
    epoch: u64,
    mutation: bool,
}
impl Drop for PermitInner {
    fn drop(&mut self) {
        if self.mutation {
            self.authority.mutations.fetch_sub(1, Ordering::SeqCst);
        }
    }
}

tokio::task_local! { static PUBLIC_PERMIT: Option<Permit>; }

pub fn current_permit() -> Option<Permit> {
    PUBLIC_PERMIT.try_with(Clone::clone).ok().flatten()
}

pub async fn scope<T>(permit: Option<Permit>, future: impl Future<Output = T>) -> T {
    PUBLIC_PERMIT.scope(permit, future).await
}

impl ServingAuthority {
    pub fn new(identity: Holder, enabled: bool) -> Arc<Self> {
        Arc::new(Self {
            identity,
            enabled,
            active: Mutex::new(None),
            observed: Mutex::new(None),
            mutations: AtomicUsize::new(0),
            barrier: Mutex::new(None),
            marker: None,
            revoked_epoch: std::sync::atomic::AtomicU64::new(0),
            store: Mutex::new(None),
        })
    }

    pub fn legacy() -> Arc<Self> {
        Self::new(
            Holder {
                instance_uid: String::new(),
                pod_uid: String::new(),
                incarnation: uuid::Uuid::now_v7().to_string(),
                host: String::new(),
            },
            false,
        )
    }

    pub fn install(&self, grant: Grant) -> Result<(), String> {
        let mut active = self
            .active
            .lock()
            .map_err(|_| "serving authority poisoned")?;
        if grant.holder.instance_uid != self.identity.instance_uid {
            *active = None;
            return Err("instance mismatch".into());
        }
        {
            let mut observed = self
                .observed
                .lock()
                .map_err(|_| "authority observation poisoned")?;
            if observed.as_ref().is_some_and(|old| {
                old.epoch > grant.epoch
                    || (old.epoch == grant.epoch
                        && (old.expires_ms > grant.expires_ms
                            || (old.phase == "Revoking" && grant.phase != "Revoking")))
            }) {
                return Err("grant regression".into());
            }
            *observed = Some(grant.clone());
        }

        if grant.holder == self.identity && grant.phase == "Revoking" {
            if self.revoked_epoch.load(Ordering::SeqCst) == grant.epoch {
                return Ok(());
            }
            let old = active.as_mut().ok_or("no live grant to revoke")?;
            validate(old, grant.epoch)?;
            old.grant.phase = "Revoking".into();
            if self.mutations() != 0 {
                return Err("mutations still settling".into());
            }
            self.require_retained_barrier(&grant)?;
            if let Some(marker) = &self.marker {
                std::fs::remove_file(marker).map_err(|e| e.to_string())?;
                std::fs::File::open(marker.parent().ok_or("missing marker parent")?)
                    .and_then(|f| f.sync_all())
                    .map_err(|e| e.to_string())?;
            }
            self.revoked_epoch.store(grant.epoch, Ordering::SeqCst);
            *active = None;
            return Ok(());
        }
        if !matches!(grant.phase.as_str(), "Quiescing" | "Revoking") {
            // An authoritative abort or completed transfer releases the corpus.
            // A newly promoted destination must still hold the exact receipt;
            // a restarted or timed-out preparation can never authorize serving.
            if grant.holder == self.identity && grant.barrier.is_some() && active.is_none() {
                self.require_retained_barrier(&grant)?;
            }
            if let Some(store) = self
                .store
                .lock()
                .map_err(|_| "store binding poisoned")?
                .as_ref()
            {
                *store
                    .handover_hold
                    .lock()
                    .map_err(|_| "handover hold poisoned")? = None;
            }
        }
        if grant.holder != self.identity || grant.phase == "Preparing" || grant.phase == "Fencing" {
            *active = None;
            return Ok(());
        }
        if grant.epoch == 0 || !matches!(grant.phase.as_str(), "Serving" | "Quiescing") {
            *active = None;
            return Err("grant identity or phase mismatch".into());
        }
        let now = now_ms();
        if grant.expires_ms <= now + 2_000 || grant.expires_ms > now + 15_000 {
            *active = None;
            return Err("grant outside lifetime bounds".into());
        }
        if active.as_ref().is_some_and(|a| {
            grant.epoch < a.grant.epoch
                || (grant.epoch == a.grant.epoch && grant.expires_ms < a.grant.expires_ms)
        }) {
            return Err("stale serving grant".into());
        }
        if self.revoked_epoch.load(Ordering::SeqCst) >= grant.epoch {
            return Err("revoked epoch cannot reopen".into());
        }
        if active
            .as_ref()
            .is_some_and(|a| validate(a, a.grant.epoch).is_err())
        {
            *active = None;
            return Err(
                "expired primary must be positively fenced and its volume quarantined".into(),
            );
        }
        if active.is_none()
            && let Some(marker) = &self.marker
        {
            use std::io::Write;
            let mut file = std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(marker)
                .map_err(|e| format!("primary volume needs quarantine: {e}"))?;
            file.write_all(&serde_json::to_vec(&grant).map_err(|e| e.to_string())?)
                .and_then(|_| file.sync_all())
                .map_err(|e| e.to_string())?;
            std::fs::File::open(marker.parent().ok_or("missing marker parent")?)
                .and_then(|f| f.sync_all())
                .map_err(|e| e.to_string())?;
        }
        // Re-reading the same document must never extend its monotonic deadline.
        let deadline = Instant::now() + Duration::from_millis(grant.expires_ms - now - 2_000);
        let deadline = active
            .as_ref()
            .filter(|a| a.grant.epoch == grant.epoch && a.grant.expires_ms == grant.expires_ms)
            .map_or(deadline, |a| a.deadline.min(deadline));
        *active = Some(Active { grant, deadline });
        Ok(())
    }

    #[cfg(test)]
    pub fn admit(self: &Arc<Self>) -> Result<Option<Permit>, String> {
        self.admit_request(true)
    }

    pub fn admit_request(self: &Arc<Self>, mutation: bool) -> Result<Option<Permit>, String> {
        if !self.enabled {
            return Ok(None);
        }
        let active = self
            .active
            .lock()
            .map_err(|_| "serving authority poisoned")?;
        let active = active.as_ref().ok_or("no serving grant")?;
        validate(active, active.grant.epoch)?;
        if !matches!(active.grant.phase.as_str(), "Serving" | "Quiescing") {
            return Err("primary revoked".into());
        }
        if mutation && active.grant.phase != "Serving" {
            return Err("primary is quiescing".into());
        }
        if mutation {
            self.mutations.fetch_add(1, Ordering::SeqCst);
        }
        Ok(Some(Permit(Arc::new(PermitInner {
            authority: self.clone(),
            epoch: active.grant.epoch,
            mutation,
        }))))
    }

    pub fn identity(&self) -> &Holder {
        &self.identity
    }
    pub fn bind_store(&self, store: Arc<crate::store::Store>) {
        *self.store.lock().expect("store binding poisoned") = Some(store);
    }
    fn require_retained_barrier(&self, grant: &Grant) -> Result<(), String> {
        let expected = grant.barrier.as_ref().ok_or("missing retained barrier")?;
        if self
            .barrier
            .lock()
            .map_err(|_| "barrier poisoned")?
            .as_ref()
            != Some(expected)
        {
            return Err("retained barrier does not match this incarnation".into());
        }
        let binding = self.store.lock().map_err(|_| "store binding poisoned")?;
        let store = binding.as_ref().ok_or("store not bound")?;
        if store
            .handover_hold
            .lock()
            .map_err(|_| "handover hold poisoned")?
            .as_deref()
            != Some(expected.id.as_str())
        {
            return Err("retained corpus no longer held".into());
        }
        Ok(())
    }
    pub fn intent(&self) -> Option<Grant> {
        self.observed.lock().ok()?.clone()
    }
    pub fn mutations(&self) -> usize {
        self.mutations.load(Ordering::SeqCst)
    }
    pub fn enabled(&self) -> bool {
        self.enabled
    }
    pub fn peer_safe(&self) -> bool {
        if !self.enabled {
            return true;
        }
        let active = self.active.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(active) = active.as_ref() {
            return validate(active, active.grant.epoch).is_ok();
        }
        self.marker.as_ref().is_none_or(|path| !path.exists())
    }
    pub fn report(&self) -> serde_json::Value {
        let active = self.active.lock().unwrap_or_else(|e| e.into_inner());
        let valid = active
            .as_ref()
            .is_some_and(|a| validate(a, a.grant.epoch).is_ok());
        serde_json::json!({"capability": "positive-fence-v1", "enabled": self.enabled, "identity": self.identity,
            "epoch": active.as_ref().map_or(0, |a| a.grant.epoch), "valid": valid,
            "remaining_ms": active.as_ref().map_or(0, |a| a.grant.expires_ms.saturating_sub(now_ms() + 2000)),
            "automatic_partition_promotion": false, "observed": self.intent(), "mutations": self.mutations(), "revoked_epoch": self.revoked_epoch.load(Ordering::SeqCst), "barrier": *self.barrier.lock().unwrap_or_else(|e| e.into_inner())})
    }
}

fn validate(active: &Active, epoch: u64) -> Result<(), String> {
    if active.grant.epoch != epoch
        || Instant::now() >= active.deadline
        || now_ms() + 2000 >= active.grant.expires_ms
    {
        Err("serving grant expired or superseded".into())
    } else {
        Ok(())
    }
}

impl Permit {
    pub fn check(&self) -> Result<(), String> {
        let active = self
            .0
            .authority
            .active
            .lock()
            .map_err(|_| "serving authority poisoned")?;
        validate(
            active.as_ref().ok_or("serving grant revoked")?,
            self.0.epoch,
        )
    }

    // Hold the authority mutex through synchronous metadata publication. A
    // revoke cannot acknowledge while this operation is paused. There is no
    // bounded disk/OS critical section: never promote on timeout alone.
    pub fn publish<T>(&self, operation: impl FnOnce() -> Result<T, String>) -> Result<T, String> {
        let active = self
            .0
            .authority
            .active
            .lock()
            .map_err(|_| "serving authority poisoned")?;
        validate(
            active.as_ref().ok_or("serving grant revoked")?,
            self.0.epoch,
        )?;
        let result = operation()?;
        validate(
            active.as_ref().ok_or("serving grant revoked")?,
            self.0.epoch,
        )?;
        Ok(result)
    }
}

pub fn publish<T>(
    permit: Option<&Permit>,
    operation: impl FnOnce() -> Result<T, String>,
) -> Result<T, String> {
    match permit {
        Some(p) => p.publish(operation),
        None => operation(),
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .try_into()
        .unwrap_or(u64::MAX)
}

#[derive(Clone, Debug)]
pub struct AuthorityConfig {
    pub instance: String,
    pub namespace: String,
    pub instance_uid: String,
    pub pod_uid: String,
    pub host: String,
}

impl AuthorityConfig {
    pub fn validate_volume(
        data_dir: &std::path::Path,
        config: Option<&Self>,
    ) -> Result<(), String> {
        use std::io::Write;
        if data_dir.join(".kura.primary-unclean").exists() {
            return Err("unclean primary volume: quarantine and rebuild before rejoining; never delete its marker to bypass fencing".into());
        }
        let floor = data_dir.join(".kura.serving-floor");
        match (std::fs::read_to_string(&floor), config) {
            (Ok(uid), Some(config)) if uid == config.instance_uid => Ok(()),
            (Ok(_), _) => Err("volume requires its original serving authority; legacy startup and identity reset are forbidden".into()),
            (Err(error), _) if error.kind() != std::io::ErrorKind::NotFound => Err(error.to_string()),
            (Err(_), None) => Ok(()),
            (Err(_), Some(config)) => {
                std::fs::create_dir_all(data_dir).map_err(|e| e.to_string())?;
                let mut file = std::fs::OpenOptions::new().write(true).create_new(true).open(floor).map_err(|e| e.to_string())?;
                file.write_all(config.instance_uid.as_bytes()).and_then(|_| file.sync_all()).map_err(|e| e.to_string())?;
                std::fs::File::open(data_dir).and_then(|f| f.sync_all()).map_err(|e| e.to_string())
            }
        }
    }
    pub fn from_env() -> Result<Option<Self>, String> {
        let Some(instance) = std::env::var("KURA_SERVING_AUTHORITY").ok() else {
            return Ok(None);
        };
        let required = |name| {
            std::env::var(name)
                .ok()
                .filter(|v| !v.is_empty())
                .ok_or_else(|| format!("{name} is required for serving authority"))
        };
        if instance.is_empty() {
            return Err("KURA_SERVING_AUTHORITY must not be empty".into());
        }
        Ok(Some(Self {
            instance,
            namespace: required("POD_NAMESPACE")?,
            instance_uid: required("KURA_INSTANCE_UID")?,
            pod_uid: required("POD_UID")?,
            host: required("POD_NODE_NAME")?,
        }))
    }

    pub fn start(&self, data_dir: &std::path::Path) -> Result<Arc<ServingAuthority>, String> {
        let mut authority = ServingAuthority::new(
            Holder {
                instance_uid: self.instance_uid.clone(),
                pod_uid: self.pod_uid.clone(),
                incarnation: uuid::Uuid::now_v7().to_string(),
                host: self.host.clone(),
            },
            true,
        );
        Arc::get_mut(&mut authority)
            .expect("unshared authority")
            .marker = Some(data_dir.join(".kura.primary-unclean"));
        let ca = std::fs::read("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")
            .map_err(|e| e.to_string())?;
        let certificate = reqwest::Certificate::from_pem(&ca).map_err(|e| e.to_string())?;
        let config = self.clone();
        let worker = authority.clone();
        std::thread::Builder::new().name("serving-authority".into()).spawn(move || {
            let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().expect("authority runtime");
            runtime.block_on(async move {
                let client = reqwest::Client::builder().add_root_certificate(certificate).https_only(true).no_proxy().redirect(reqwest::redirect::Policy::none()).timeout(Duration::from_secs(1)).build().expect("authority client");
                let url = format!("https://kubernetes.default.svc/api/v1/namespaces/{}/configmaps/{}-serving", config.namespace, config.instance);
                loop {
                    let result = async {
                        let token = tokio::fs::read_to_string("/var/run/secrets/kubernetes.io/serviceaccount/token").await.map_err(|e| e.to_string())?;
                        let response = client.get(&url).bearer_auth(token.trim()).send().await.map_err(|e| e.to_string())?.error_for_status().map_err(|e| e.to_string())?;
                        let document: serde_json::Value = response.json().await.map_err(|e| e.to_string())?;
                        let grant = document["data"]["grant"].as_str().ok_or("no grant")?;
                        worker.install(serde_json::from_str(grant).map_err(|e| e.to_string())?)
                    }.await;
                    if let Err(error) = result { tracing::warn!(event.name = "kura.serving_authority.unavailable", %error); }
                    tokio::time::sleep(Duration::from_secs(1)).await;
                }
            });
        }).map_err(|e| e.to_string())?;
        Ok(authority)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn authority() -> Arc<ServingAuthority> {
        ServingAuthority::new(
            Holder {
                instance_uid: "i".into(),
                pod_uid: "p".into(),
                incarnation: "r".into(),
                host: "h".into(),
            },
            true,
        )
    }
    fn grant(a: &ServingAuthority, epoch: u64) -> Grant {
        Grant {
            epoch,
            holder: a.identity.clone(),
            expires_ms: now_ms() + 15000,
            phase: "Serving".into(),
            handover: None,
            barrier: None,
        }
    }
    #[test]
    fn startup_is_closed_and_identity_is_exact() {
        let a = authority();
        assert!(a.admit().is_err());
        for field in [0, 1, 2, 3] {
            let mut g = grant(&a, 1);
            match field {
                0 => g.holder.instance_uid.push('x'),
                1 => g.holder.pod_uid.push('x'),
                2 => g.holder.incarnation.push('x'),
                _ => g.holder.host.push('x'),
            };
            let _ = a.install(g);
            assert!(a.admit().is_err());
        }
    }
    #[test]
    fn old_permit_cannot_publish_after_epoch_change_or_pause() {
        let a = authority();
        a.install(grant(&a, 1)).unwrap();
        let p = a.admit().unwrap().unwrap();
        a.install(grant(&a, 2)).unwrap();
        assert!(p.publish::<()>(|| panic!("old epoch published")).is_err());
        let p = a.admit().unwrap().unwrap();
        a.active.lock().unwrap().as_mut().unwrap().deadline = Instant::now();
        assert!(
            p.publish::<()>(|| panic!("expired write published"))
                .is_err()
        );
        assert!(a.admit().is_err());
    }
    #[test]
    fn rereading_grant_never_renews_monotonic_deadline() {
        let a = authority();
        let g = grant(&a, 1);
        a.install(g.clone()).unwrap();
        let deadline = a.active.lock().unwrap().as_ref().unwrap().deadline;
        a.install(g).unwrap();
        assert!(a.active.lock().unwrap().as_ref().unwrap().deadline <= deadline);
    }
    #[test]
    fn quiescing_rejects_new_requests_but_allows_existing_permits() {
        let a = authority();
        let mut g = grant(&a, 1);
        a.install(g.clone()).unwrap();
        let p = a.admit().unwrap().unwrap();
        g.phase = "Quiescing".into();
        a.install(g).unwrap();
        assert!(a.admit().is_err());
        assert!(p.publish(|| Ok(())).is_ok());
    }

    #[tokio::test]
    async fn expired_admitted_write_cannot_publish_a_real_inline_manifest() {
        let ctx = crate::test_support::test_context(|_| {}).await;
        let a = authority();
        a.install(grant(&a, 1)).unwrap();
        let permit = a.admit().unwrap();
        a.active.lock().unwrap().as_mut().unwrap().deadline = Instant::now();
        let result = scope(
            permit,
            ctx.state.store.persist_inline_artifact_from_bytes(
                crate::artifact::producer::ArtifactProducer::Xcode,
                "tenant/project",
                "expired",
                "text/plain",
                b"must not publish",
            ),
        )
        .await;
        assert!(result.is_err());
        assert_eq!(a.mutations(), 0);
    }

    #[test]
    fn dirty_volume_cannot_reopen_after_expiry_or_restart() {
        let dir = tempfile::tempdir().unwrap();
        let mut a = authority();
        let marker = dir.path().join(".kura.primary-unclean");
        Arc::get_mut(&mut a).unwrap().marker = Some(marker.clone());
        a.install(grant(&a, 1)).unwrap();
        assert!(marker.exists());
        a.active.lock().unwrap().as_mut().unwrap().deadline = Instant::now();
        assert!(a.install(grant(&a, 1)).is_err());
        assert!(a.install(grant(&a, 2)).is_err());
        assert!(!a.peer_safe());
        let mut restarted = authority();
        Arc::get_mut(&mut restarted).unwrap().marker = Some(marker);
        assert!(restarted.install(grant(&restarted, 2)).is_err());
        assert!(!restarted.peer_safe());
    }

    #[test]
    fn revocation_cannot_acknowledge_without_a_retained_barrier() {
        let a = authority();
        let mut g = grant(&a, 1);
        a.install(g.clone()).unwrap();
        g.phase = "Revoking".into();
        assert!(a.install(g).is_err());
        assert_eq!(a.revoked_epoch.load(Ordering::SeqCst), 0);
        assert!(a.admit().is_err());
    }

    #[test]
    fn standby_volume_enforces_rollback_floor_and_instance_identity() {
        let dir = tempfile::tempdir().unwrap();
        let mut config = AuthorityConfig {
            instance: "i".into(),
            namespace: "n".into(),
            instance_uid: "uid".into(),
            pod_uid: "p".into(),
            host: "h".into(),
        };
        AuthorityConfig::validate_volume(dir.path(), Some(&config)).unwrap();
        AuthorityConfig::validate_volume(dir.path(), Some(&config)).unwrap();
        assert!(AuthorityConfig::validate_volume(dir.path(), None).is_err());
        config.instance_uid.push('x');
        assert!(AuthorityConfig::validate_volume(dir.path(), Some(&config)).is_err());
    }
}
