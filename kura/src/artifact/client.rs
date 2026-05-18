use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ArtifactClient {
    Generic,
    Xcode,
    Gradle,
    Module,
}

impl ArtifactClient {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Generic => "generic",
            Self::Xcode => "xcode",
            Self::Gradle => "gradle",
            Self::Module => "module",
        }
    }
}
