
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
