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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resume_epoch: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub exit_resume: Option<ExitResume>,
}

/// The kubelet-attested exited holder whose unclean volume a restarted
/// container in the same pod takes the writer over from.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct ExitResume {
    pub epoch: u64,
    pub holder: Holder,
}

const UNCLEAN_VOLUME: &str = "unclean primary volume: quarantine and rebuild before rejoining; never delete its marker to bypass fencing";
const TERMINATION_LOG: &str = "/dev/termination-log";

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
    pub(crate) handover_preparation: tokio::sync::Mutex<()>,
    pub(crate) preparation: Mutex<Option<crate::handover::Preparation>>,
    marker: Option<std::path::PathBuf>,
    // The exited holder that left this pod's volume marked. Until its exit
    // resume installs, no other grant may open the volume.
    inherited: Mutex<Option<Holder>>,
    exit_attested: std::sync::atomic::AtomicBool,
    revoked_epoch: std::sync::atomic::AtomicU64,
    // These attestations exist only in the process that owned the writer. They
    // never authorize another incarnation to open an unclean volume.
    owned_epoch: std::sync::atomic::AtomicU64,
    fenced_epoch: std::sync::atomic::AtomicU64,
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
            handover_preparation: tokio::sync::Mutex::new(()),
            preparation: Mutex::new(None),
            marker: None,
            inherited: Mutex::new(None),
            exit_attested: std::sync::atomic::AtomicBool::new(false),
            revoked_epoch: std::sync::atomic::AtomicU64::new(0),
            owned_epoch: std::sync::atomic::AtomicU64::new(0),
            fenced_epoch: std::sync::atomic::AtomicU64::new(0),
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

        if grant.holder == self.identity && grant.phase == "Fencing" {
            // Taking this lock joins every synchronous publication, including
            // one suspended beyond its deadline. Clearing active prevents all
            // admitted work from publishing; wait for that work to drop before
            // attesting. Keep the marker: this is not a clean standby/restart.
            *active = None;
            let owned = self.owned_epoch.load(Ordering::SeqCst);
            // A replacement grant can itself expire before delivery. The
            // persisted resume binding still names this already-fenced writer;
            // join publication again and acknowledge the skipped epoch too.
            let missed_resume = owned != 0
                && grant.resume_epoch == Some(owned)
                && owned.checked_add(1) == Some(grant.epoch)
                && self.fenced_epoch.load(Ordering::SeqCst) == owned;
            if grant.epoch != 0
                && grant.handover.is_none()
                && (owned == grant.epoch || missed_resume)
                && self.revoked_epoch.load(Ordering::SeqCst) < grant.epoch
                && self.mutations() == 0
            {
                self.owned_epoch.store(grant.epoch, Ordering::SeqCst);
                self.fenced_epoch.store(grant.epoch, Ordering::SeqCst);
            }
            return Ok(());
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
            return Err("expired primary requires positive fencing before serving again".into());
        }
        let resuming = grant.resume_epoch.is_some()
            && active
                .as_ref()
                .is_none_or(|old| old.grant.epoch != grant.epoch);
        if resuming {
            let epoch = grant.resume_epoch.ok_or("missing resume epoch")?;
            if epoch == 0
                || active.is_some()
                || epoch.checked_add(1) != Some(grant.epoch)
                || self.owned_epoch.load(Ordering::SeqCst) != epoch
                || self.fenced_epoch.load(Ordering::SeqCst) != epoch
                || self.mutations() != 0
                || grant.phase != "Serving"
                || grant.handover.is_some()
                || grant.barrier.is_some()
            {
                return Err(
                    "resume requires this live writer's positive fencing acknowledgment".into(),
                );
            }
        }
        let mut inherited = self
            .inherited
            .lock()
            .map_err(|_| "inherited holder poisoned")?;
        if active.is_none() && inherited.is_some() {
            // A restarted container in the exited holder's own pod takes the
            // writer over only through a grant naming that exact predecessor.
            // Without an inherited volume the binding authorizes nothing, and a
            // grant still carrying an earlier one follows the ordinary rules.
            let exit = grant.exit_resume.as_ref();
            if resuming
                || exit.map(|exit| &exit.holder) != inherited.as_ref()
                || exit.is_none_or(|exit| {
                    exit.holder.pod_uid != self.identity.pod_uid
                        || exit.holder.host != self.identity.host
                        || exit.holder.incarnation == self.identity.incarnation
                        || exit.epoch >= grant.epoch
                })
                || grant.phase != "Serving"
                || grant.handover.is_some()
                || grant.barrier.is_some()
                || self.mutations() != 0
            {
                return Err(
                    "unclean primary volume accepts only an exit resume from its own exited holder"
                        .into(),
                );
            }
        }
        if active.is_none()
            && !resuming
            && let Some(marker) = &self.marker
        {
            if inherited.is_some() {
                replace_marker(marker, &grant)?;
            } else {
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
        }
        *inherited = None;
        // Re-reading the same document must never extend its monotonic deadline.
        let deadline = Instant::now() + Duration::from_millis(grant.expires_ms - now - 2_000);
        let deadline = active
            .as_ref()
            .filter(|a| a.grant.epoch == grant.epoch && a.grant.expires_ms == grant.expires_ms)
            .map_or(deadline, |a| a.deadline.min(deadline));
        *active = Some(Active { grant, deadline });
        self.owned_epoch.store(
            active.as_ref().expect("installed grant").grant.epoch,
            Ordering::SeqCst,
        );
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
    /// An inherited unclean volume serves nothing until its exit resume installs,
    /// and after another holder is promoted it never will.
    pub fn awaiting_exit_resume(&self) -> bool {
        self.inherited
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .is_some()
    }
    /// kubelet reports this file as the terminated container's message however
    /// the process ended, naming the exact incarnation that no longer runs.
    fn attest_incarnation(&self, path: &std::path::Path) {
        let attested = std::fs::write(
            path,
            format!("kura-incarnation={}", self.identity.incarnation),
        );
        if let Err(error) = &attested {
            tracing::warn!(event.name = "kura.serving_authority.exit_attestation_unavailable", %error);
        }
        self.exit_attested.store(attested.is_ok(), Ordering::SeqCst);
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
            "preparation_supported": true, "preparation": *self.preparation.lock().unwrap_or_else(|e| e.into_inner()),
            "automatic_partition_promotion": false, "observed": self.intent(), "mutations": self.mutations(), "revoked_epoch": self.revoked_epoch.load(Ordering::SeqCst), "fenced_epoch": self.fenced_epoch.load(Ordering::SeqCst), "barrier": *self.barrier.lock().unwrap_or_else(|e| e.into_inner()),
            "exit_attested": self.exit_attested.load(Ordering::SeqCst), "exit_resume": *self.inherited.lock().unwrap_or_else(|e| e.into_inner())})
    }
}

fn replace_marker(marker: &std::path::Path, grant: &Grant) -> Result<(), String> {
    use std::io::Write;
    let staged = marker.with_extension("exit-resume");
    let mut file = std::fs::File::create(&staged).map_err(|e| e.to_string())?;
    file.write_all(&serde_json::to_vec(grant).map_err(|e| e.to_string())?)
        .and_then(|_| file.sync_all())
        .map_err(|e| e.to_string())?;
    std::fs::rename(&staged, marker).map_err(|e| e.to_string())?;
    std::fs::File::open(marker.parent().ok_or("missing marker parent")?)
        .and_then(|f| f.sync_all())
        .map_err(|e| e.to_string())
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

fn authority_http_error(error: reqwest::Error) -> String {
    use std::error::Error;
    let mut details = format!(
        "timeout={} connect={} {error}",
        error.is_timeout(),
        error.is_connect()
    );
    let mut cause = error.source();
    for _ in 0..8 {
        let Some(error) = cause else { break };
        details.push_str(": ");
        details.extend(error.to_string().chars().take(256));
        cause = error.source();
    }
    details.chars().take(2048).collect()
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
    /// Returns the exited holder when the volume is this pod's own unclean
    /// primary volume. Only that holder's exit resume may reopen it; any other
    /// pod, or a legacy start, must quarantine and rebuild.
    pub fn validate_volume(
        data_dir: &std::path::Path,
        config: Option<&Self>,
    ) -> Result<Option<Holder>, String> {
        use std::io::Write;
        let inherited = match (
            std::fs::read(data_dir.join(".kura.primary-unclean")),
            config,
        ) {
            (Err(error), _) if error.kind() == std::io::ErrorKind::NotFound => None,
            (Err(error), _) => return Err(error.to_string()),
            (Ok(marker), Some(config)) => match serde_json::from_slice::<Grant>(&marker) {
                Ok(grant)
                    if grant.holder.instance_uid == config.instance_uid
                        && grant.holder.pod_uid == config.pod_uid
                        && grant.holder.host == config.host =>
                {
                    Some(grant.holder)
                }
                _ => return Err(UNCLEAN_VOLUME.into()),
            },
            (Ok(_), None) => return Err(UNCLEAN_VOLUME.into()),
        };
        let floor = data_dir.join(".kura.serving-floor");
        match (std::fs::read_to_string(&floor), config) {
            (Ok(uid), Some(config)) if uid == config.instance_uid => Ok(inherited),
            (Ok(_), _) => Err("volume requires its original serving authority; legacy startup and identity reset are forbidden".into()),
            (Err(error), _) if error.kind() != std::io::ErrorKind::NotFound => Err(error.to_string()),
            (Err(_), None) => Ok(None),
            (Err(_), Some(_)) if inherited.is_some() => Err(UNCLEAN_VOLUME.into()),
            (Err(_), Some(config)) => {
                std::fs::create_dir_all(data_dir).map_err(|e| e.to_string())?;
                let mut file = std::fs::OpenOptions::new().write(true).create_new(true).open(floor).map_err(|e| e.to_string())?;
                file.write_all(config.instance_uid.as_bytes()).and_then(|_| file.sync_all()).map_err(|e| e.to_string())?;
                std::fs::File::open(data_dir).and_then(|f| f.sync_all()).map_err(|e| e.to_string())?;
                Ok(None)
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

    pub fn start(
        &self,
        data_dir: &std::path::Path,
        inherited: Option<Holder>,
    ) -> Result<Arc<ServingAuthority>, String> {
        let mut authority = ServingAuthority::new(
            Holder {
                instance_uid: self.instance_uid.clone(),
                pod_uid: self.pod_uid.clone(),
                incarnation: uuid::Uuid::now_v7().to_string(),
                host: self.host.clone(),
            },
            true,
        );
        {
            let unshared = Arc::get_mut(&mut authority).expect("unshared authority");
            unshared.marker = Some(data_dir.join(".kura.primary-unclean"));
            *unshared.inherited.get_mut().expect("unshared inheritance") = inherited;
        }
        authority.attest_incarnation(std::path::Path::new(TERMINATION_LOG));
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
                        let response = client.get(&url).bearer_auth(token.trim()).send().await.map_err(authority_http_error)?.error_for_status().map_err(authority_http_error)?;
                        let document: serde_json::Value = response.json().await.map_err(authority_http_error)?;
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
            resume_epoch: None,
            exit_resume: None,
        }
    }
    #[test]
    fn serving_preparation_keeps_mutations_admitted_until_quiescing() {
        let authority = authority();
        let mut grant = grant(&authority, 1);
        let mut destination = authority.identity().clone();
        destination.pod_uid = "standby".into();
        grant.handover = Some(crate::handover::Intent {
            id: "prepare".into(),
            destination,
            source_url: "http://source".into(),
            destination_url: "http://standby".into(),
            deadline_ms: now_ms() + 1_200_000,
        });
        authority.install(grant.clone()).unwrap();
        let permit = authority.admit().unwrap().unwrap();
        permit.publish(|| Ok(())).unwrap();
        drop(permit);
        grant.phase = "Quiescing".into();
        grant.handover.as_mut().unwrap().deadline_ms = now_ms() + 300_000;
        authority.install(grant).unwrap();
        assert!(authority.admit().is_err());
        assert!(authority.admit_request(false).is_ok());
        assert!(authority.barrier.lock().unwrap().is_none());
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
    fn same_live_writer_resumes_only_after_publication_fencing_and_drain() {
        let dir = tempfile::tempdir().unwrap();
        let mut a = authority();
        let marker = dir.path().join(".kura.primary-unclean");
        Arc::get_mut(&mut a).unwrap().marker = Some(marker.clone());
        a.install(grant(&a, 1)).unwrap();
        let read = a.admit_request(false).unwrap().unwrap();
        let write = a.admit().unwrap().unwrap();
        a.active.lock().unwrap().as_mut().unwrap().deadline = Instant::now();
        assert!(a.install(grant(&a, 1)).is_err());
        let mut fence = grant(&a, 1);
        fence.phase = "Fencing".into();
        a.install(fence.clone()).unwrap();
        assert_eq!(a.report()["fenced_epoch"], 0);
        assert!(
            write
                .publish::<()>(|| panic!("late write published"))
                .is_err()
        );
        drop(write);
        a.install(fence).unwrap();
        assert_eq!(a.report()["fenced_epoch"], 1);
        assert!(!a.peer_safe());
        assert!(marker.exists());

        let mut resume = grant(&a, 2);
        resume.resume_epoch = Some(1);
        a.install(resume.clone()).unwrap();
        a.install(resume).unwrap();
        assert!(a.peer_safe());
        assert!(a.admit().is_ok());
        assert!(
            read.check().is_err(),
            "old channel permit survived new epoch"
        );
        assert!(
            marker.exists(),
            "resumption must not make the volume restartable"
        );

        let mut restarted = authority();
        Arc::get_mut(&mut restarted).unwrap().marker = Some(marker);
        let mut fence = grant(&restarted, 2);
        fence.phase = "Fencing".into();
        restarted.install(fence).unwrap();
        assert_eq!(restarted.report()["fenced_epoch"], 0);
        let mut resume = grant(&restarted, 3);
        resume.resume_epoch = Some(2);
        assert!(restarted.install(resume).is_err());
        assert!(!restarted.peer_safe());
    }

    #[test]
    fn fencing_acknowledgment_waits_for_a_suspended_publication() {
        let a = authority();
        a.install(grant(&a, 1)).unwrap();
        let permit = a.admit().unwrap().unwrap();
        let (entered_tx, entered_rx) = std::sync::mpsc::channel();
        let (release_tx, release_rx) = std::sync::mpsc::channel();
        let writer = std::thread::spawn(move || {
            permit
                .publish(|| {
                    entered_tx.send(()).unwrap();
                    release_rx.recv().unwrap();
                    Ok(())
                })
                .unwrap();
        });
        entered_rx.recv().unwrap();
        let mut fence = grant(&a, 1);
        fence.phase = "Fencing".into();
        let worker = a.clone();
        let (ack_tx, ack_rx) = std::sync::mpsc::channel();
        let fencer = std::thread::spawn(move || {
            worker.install(fence.clone()).unwrap();
            ack_tx.send(()).unwrap();
            fence
        });
        assert!(ack_rx.recv_timeout(Duration::from_millis(50)).is_err());
        assert_eq!(a.fenced_epoch.load(Ordering::SeqCst), 0);
        release_tx.send(()).unwrap();
        writer.join().unwrap();
        let fence = fencer.join().unwrap();
        a.install(fence).unwrap();
        assert_eq!(a.report()["fenced_epoch"], 1);
        assert!(a.admit().is_err());
    }

    #[test]
    fn a_resume_grant_lost_until_expiry_can_be_fenced_without_reopening_it() {
        let dir = tempfile::tempdir().unwrap();
        let mut a = authority();
        let marker = dir.path().join(".kura.primary-unclean");
        Arc::get_mut(&mut a).unwrap().marker = Some(marker.clone());
        a.install(grant(&a, 1)).unwrap();
        let old = a.admit_request(false).unwrap().unwrap();
        let mut fence = grant(&a, 1);
        fence.phase = "Fencing".into();
        a.install(fence.clone()).unwrap();
        for epoch in 2..=3 {
            let mut missed = grant(&a, epoch);
            missed.resume_epoch = Some(epoch - 1);
            missed.expires_ms = now_ms();
            assert!(a.install(missed.clone()).is_err());
            assert!(a.admit().is_err());
            missed.phase = "Fencing".into();
            a.install(missed).unwrap();
            assert_eq!(a.report()["fenced_epoch"], epoch);
            assert!(marker.exists());
        }
        let mut resumed = grant(&a, 4);
        resumed.resume_epoch = Some(3);
        a.install(resumed).unwrap();
        assert!(a.admit().is_ok());
        assert!(old.check().is_err());
        assert!(marker.exists());
    }

    #[test]
    fn resume_cannot_skip_fencing_or_change_the_epoch_binding() {
        for (fenced, resume_epoch, next_epoch) in
            [(false, 1, 2), (true, 0, 2), (true, 1, 3), (true, 2, 3)]
        {
            let a = authority();
            a.install(grant(&a, 1)).unwrap();
            if fenced {
                let mut fence = grant(&a, 1);
                fence.phase = "Fencing".into();
                a.install(fence).unwrap();
            } else {
                a.active.lock().unwrap().as_mut().unwrap().deadline = Instant::now();
            }
            let mut resume = grant(&a, next_epoch);
            resume.resume_epoch = Some(resume_epoch);
            assert!(a.install(resume).is_err());
            assert!(a.admit().is_err());
        }
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

    fn restarted(previous: &ServingAuthority, marker: std::path::PathBuf) -> Arc<ServingAuthority> {
        let mut identity = previous.identity.clone();
        identity.incarnation.push_str("-restarted");
        let mut restarted = ServingAuthority::new(identity, true);
        let unshared = Arc::get_mut(&mut restarted).unwrap();
        unshared.marker = Some(marker);
        *unshared.inherited.get_mut().unwrap() = Some(previous.identity.clone());
        restarted
    }

    fn exit_resume(restarted: &ServingAuthority, previous: &Holder, epoch: u64) -> Grant {
        let mut grant = grant(restarted, epoch + 1);
        grant.exit_resume = Some(ExitResume {
            epoch,
            holder: previous.clone(),
        });
        grant
    }

    #[test]
    fn only_the_same_pod_inherits_its_unclean_volume() {
        let dir = tempfile::tempdir().unwrap();
        let config = AuthorityConfig {
            instance: "i".into(),
            namespace: "n".into(),
            instance_uid: "i".into(),
            pod_uid: "p".into(),
            host: "h".into(),
        };
        assert_eq!(
            AuthorityConfig::validate_volume(dir.path(), Some(&config)).unwrap(),
            None
        );
        let mut a = authority();
        Arc::get_mut(&mut a).unwrap().marker = Some(dir.path().join(".kura.primary-unclean"));
        a.install(grant(&a, 1)).unwrap();
        assert_eq!(
            AuthorityConfig::validate_volume(dir.path(), Some(&config)).unwrap(),
            Some(a.identity.clone())
        );
        assert!(AuthorityConfig::validate_volume(dir.path(), None).is_err());
        for field in 0..3 {
            let mut other = config.clone();
            match field {
                0 => other.pod_uid.push('x'),
                1 => other.host.push('x'),
                _ => other.instance_uid.push('x'),
            }
            assert!(AuthorityConfig::validate_volume(dir.path(), Some(&other)).is_err());
        }
    }

    #[test]
    fn a_restarted_container_takes_over_only_from_its_exited_holder() {
        let dir = tempfile::tempdir().unwrap();
        let marker = dir.path().join(".kura.primary-unclean");
        let mut a = authority();
        Arc::get_mut(&mut a).unwrap().marker = Some(marker.clone());
        a.install(grant(&a, 4)).unwrap();
        let b = restarted(&a, marker.clone());
        assert!(!b.peer_safe());
        assert!(b.awaiting_exit_resume());
        assert_eq!(b.report()["exit_resume"]["incarnation"], "r");

        assert!(
            b.install(grant(&b, 5)).is_err(),
            "an ordinary grant reopened an unclean volume"
        );
        let mut wrong_holder = a.identity.clone();
        wrong_holder.incarnation.push('x');
        assert!(b.install(exit_resume(&b, &wrong_holder, 4)).is_err());
        let mut not_newer = exit_resume(&b, &a.identity, 4);
        not_newer.epoch = 4;
        assert!(b.install(not_newer).is_err());
        let mut quiescing = exit_resume(&b, &a.identity, 4);
        quiescing.phase = "Quiescing".into();
        assert!(b.install(quiescing).is_err());
        assert!(b.admit().is_err());

        let resume = exit_resume(&b, &a.identity, 4);
        b.install(resume.clone()).unwrap();
        b.install(resume).unwrap();
        assert!(b.admit().unwrap().is_some());
        assert!(b.peer_safe());
        assert!(b.report()["exit_resume"].is_null());
        assert!(!b.awaiting_exit_resume());
        let rewritten: Grant = serde_json::from_slice(&std::fs::read(&marker).unwrap()).unwrap();
        assert_eq!(
            rewritten.holder, b.identity,
            "the marker must name the current writer"
        );

        let c = restarted(&b, marker.clone());
        assert!(
            c.install(exit_resume(&c, &a.identity, 5)).is_err(),
            "a stale predecessor resumed"
        );
        c.install(exit_resume(&c, &b.identity, 5)).unwrap();
        assert!(c.admit().unwrap().is_some());
    }

    #[test]
    fn an_exit_resume_never_opens_a_marked_volume_this_process_did_not_inherit() {
        let dir = tempfile::tempdir().unwrap();
        let marker = dir.path().join(".kura.primary-unclean");
        let mut previous = authority();
        Arc::get_mut(&mut previous).unwrap().marker = Some(marker.clone());
        previous.install(grant(&previous, 1)).unwrap();
        let mut other = authority();
        Arc::get_mut(&mut other).unwrap().marker = Some(marker);
        assert!(
            other
                .install(exit_resume(&other, &previous.identity, 1))
                .is_err()
        );
        assert!(other.admit().is_err());
    }

    #[test]
    fn a_live_writer_resumes_through_a_grant_still_naming_an_earlier_exit() {
        let dir = tempfile::tempdir().unwrap();
        let marker = dir.path().join(".kura.primary-unclean");
        let mut exited = authority();
        Arc::get_mut(&mut exited).unwrap().marker = Some(marker.clone());
        exited.install(grant(&exited, 8)).unwrap();
        let writer = restarted(&exited, marker);
        let resumed = exit_resume(&writer, &exited.identity, 8);
        writer.install(resumed.clone()).unwrap();

        // A later interruption fences this live writer; the next epoch can still
        // carry the earlier binding from a controller that kept it.
        writer.active.lock().unwrap().as_mut().unwrap().deadline = Instant::now();
        let mut fence = resumed.clone();
        fence.phase = "Fencing".into();
        writer.install(fence.clone()).unwrap();
        writer.install(fence).unwrap();
        assert_eq!(writer.report()["fenced_epoch"], 9);
        let mut resume = resumed;
        resume.epoch = 10;
        resume.resume_epoch = Some(9);
        resume.expires_ms = now_ms() + 15000;
        writer.install(resume).unwrap();
        assert!(
            writer.admit().unwrap().is_some(),
            "a stale exit binding refused the live writer"
        );
    }

    #[test]
    fn the_incarnation_is_attested_for_the_terminated_container_message() {
        let dir = tempfile::tempdir().unwrap();
        let a = authority();
        a.attest_incarnation(&dir.path().join("termination-log"));
        assert_eq!(
            std::fs::read_to_string(dir.path().join("termination-log")).unwrap(),
            "kura-incarnation=r"
        );
        assert_eq!(a.report()["exit_attested"], true);
        a.attest_incarnation(&dir.path().join("missing/termination-log"));
        assert_eq!(a.report()["exit_attested"], false);
    }
}
