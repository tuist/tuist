use serde::{Deserialize, Serialize};

use crate::artifact::{class::ArtifactClass, client::ArtifactClient};

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ArtifactKind {
    KeyValue,
    Xcode,
    Gradle,
    Module,
}

impl ArtifactKind {
    pub const fn all() -> [Self; 4] {
        [Self::KeyValue, Self::Xcode, Self::Gradle, Self::Module]
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::KeyValue => "key_value",
            Self::Xcode => "xcode",
            Self::Gradle => "gradle",
            Self::Module => "module",
        }
    }

    pub fn from_str(value: &str) -> Option<Self> {
        match value {
            "key_value" => Some(Self::KeyValue),
            "xcode" => Some(Self::Xcode),
            "gradle" => Some(Self::Gradle),
            "module" => Some(Self::Module),
            _ => None,
        }
    }

    pub fn uses_segment_storage(self) -> bool {
        !matches!(self, Self::KeyValue)
    }

    pub fn client(self) -> ArtifactClient {
        match self {
            Self::KeyValue => ArtifactClient::Generic,
            Self::Xcode => ArtifactClient::Xcode,
            Self::Gradle => ArtifactClient::Gradle,
            Self::Module => ArtifactClient::Module,
        }
    }

    pub fn artifact_class(self) -> ArtifactClass {
        match self {
            Self::KeyValue => ArtifactClass::ActionCache,
            Self::Xcode | Self::Gradle | Self::Module => ArtifactClass::Blob,
        }
    }

    pub fn from_dimensions(
        client: ArtifactClient,
        artifact_class: ArtifactClass,
    ) -> Result<Self, String> {
        match (client, artifact_class) {
            (ArtifactClient::Generic, ArtifactClass::ActionCache) => Ok(Self::KeyValue),
            (ArtifactClient::Xcode, ArtifactClass::Blob) => Ok(Self::Xcode),
            (ArtifactClient::Gradle, ArtifactClass::Blob) => Ok(Self::Gradle),
            (ArtifactClient::Module, ArtifactClass::Blob) => Ok(Self::Module),
            _ => Err(format!(
                "unsupported artifact dimensions client={} artifact_class={}",
                client.as_str(),
                artifact_class.as_str()
            )),
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::artifact::{class::ArtifactClass, client::ArtifactClient};

    use super::ArtifactKind;

    #[test]
    fn artifact_kind_roundtrips() {
        for kind in [
            ArtifactKind::KeyValue,
            ArtifactKind::Xcode,
            ArtifactKind::Gradle,
            ArtifactKind::Module,
        ] {
            assert_eq!(ArtifactKind::from_str(kind.as_str()), Some(kind));
        }
        assert_eq!(ArtifactKind::from_str("unknown"), None);
    }

    #[test]
    fn serde_roundtrips_key_value_payloads() {
        assert_eq!(
            serde_json::to_string(&ArtifactKind::KeyValue).expect("artifact kind should serialize"),
            "\"key_value\""
        );
        assert_eq!(
            serde_json::from_str::<ArtifactKind>("\"key_value\"")
                .expect("artifact kind should deserialize"),
            ArtifactKind::KeyValue
        );
    }

    #[test]
    fn only_binary_artifacts_use_segment_storage() {
        assert!(!ArtifactKind::KeyValue.uses_segment_storage());
        assert!(ArtifactKind::Xcode.uses_segment_storage());
        assert!(ArtifactKind::Gradle.uses_segment_storage());
        assert!(ArtifactKind::Module.uses_segment_storage());
    }

    #[test]
    fn normalized_metadata_dimensions_follow_kind() {
        assert_eq!(ArtifactKind::KeyValue.client().as_str(), "generic");
        assert_eq!(
            ArtifactKind::KeyValue.artifact_class().as_str(),
            "action_cache"
        );
        assert_eq!(ArtifactKind::Xcode.client().as_str(), "xcode");
        assert_eq!(ArtifactKind::Xcode.artifact_class().as_str(), "blob");
    }

    #[test]
    fn derives_kind_from_normalized_dimensions() {
        assert_eq!(
            ArtifactKind::from_dimensions(
                ArtifactKind::Gradle.client(),
                ArtifactKind::Gradle.artifact_class()
            )
            .expect("gradle dimensions should map back to gradle"),
            ArtifactKind::Gradle
        );
        assert!(
            ArtifactKind::from_dimensions(ArtifactClient::Generic, ArtifactClass::Blob).is_err()
        );
    }
}
