use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ArtifactClass {
    Blob,
    ActionCache,
}

impl ArtifactClass {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Blob => "blob",
            Self::ActionCache => "action_cache",
        }
    }
}
