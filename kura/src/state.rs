use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

use reqwest::Client;
use tokio::sync::{Mutex, Notify, RwLock};

use crate::{
    analytics::Analytics, config::Config, extension::SharedExtension, io::IoController,
    memory::MemoryController, metrics::Metrics, store::Store,
};

pub struct AppState {
    pub config: Config,
    pub store: Store,
    pub io: IoController,
    pub memory: MemoryController,
    pub metrics: Metrics,
    pub extension: Option<SharedExtension>,
    pub analytics: Option<Analytics>,
    pub client: Client,
    pub notify: Notify,
    pub members: RwLock<BTreeSet<String>>,
    pub peer_nodes: RwLock<BTreeMap<String, String>>,
    pub bootstrapped_peers: Mutex<BTreeSet<String>>,
}

pub type SharedState = Arc<AppState>;
