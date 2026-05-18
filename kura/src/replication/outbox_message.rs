use serde::{Deserialize, Serialize};

use crate::replication::operation::ReplicationOperation;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct OutboxMessage {
    pub target: String,
    pub operation: ReplicationOperation,
}
