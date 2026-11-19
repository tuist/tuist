use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct MultipartPart {
    pub path: String,
    pub size: u64,
}
