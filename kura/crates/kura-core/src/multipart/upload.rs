use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::multipart::part::MultipartPart;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct MultipartUpload {
    pub upload_id: String,
    pub tenant_id: String,
    pub namespace_id: String,
    pub category: String,
    pub hash: String,
    pub name: String,
    pub parts: BTreeMap<u32, MultipartPart>,
    pub created_at_ms: u64,
}
