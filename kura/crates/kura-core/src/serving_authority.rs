//! The parts of serving authority the store needs: the authority's configuration and the
//! request-scoped publication permit. Grants, admission and handover live in the kura crate's
//! `serving_authority` module, whose `Permit` is the only `Publisher`.
use std::{any::Any, future::Future, sync::Arc};

#[derive(Clone, Debug)]
pub struct AuthorityConfig {
    pub instance: String,
    pub namespace: String,
    pub instance_uid: String,
    pub pod_uid: String,
    pub host: String,
}

impl AuthorityConfig {
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
}

/// A serving permit that validates the grant around a metadata publication.
pub trait Publisher: Any + Send + Sync {
    /// Runs `operation` under the authority mutex, between two grant checks. A revoke cannot
    /// acknowledge while it runs.
    fn publish_dyn(&self, operation: &mut dyn FnMut() -> Result<(), String>) -> Result<(), String>;

    fn as_any(&self) -> &dyn Any;
}

pub type PermitHandle = Arc<dyn Publisher>;

tokio::task_local! { static PUBLIC_PERMIT: Option<PermitHandle>; }

pub fn current_permit() -> Option<PermitHandle> {
    PUBLIC_PERMIT.try_with(Clone::clone).ok().flatten()
}

pub async fn scope<T>(permit: Option<PermitHandle>, future: impl Future<Output = T>) -> T {
    PUBLIC_PERMIT.scope(permit, future).await
}

pub fn publish<T>(
    permit: Option<&PermitHandle>,
    operation: impl FnOnce() -> Result<T, String>,
) -> Result<T, String> {
    let Some(permit) = permit else {
        return operation();
    };
    let mut operation = Some(operation);
    let mut output = None;
    permit.publish_dyn(&mut || {
        let operation = operation
            .take()
            .expect("a publication runs its operation once");
        output = Some(operation()?);
        Ok(())
    })?;
    Ok(output.expect("a successful publication ran its operation"))
}
