
use super::ArtifactProducer;

#[test]
fn producer_roundtrips() {
    for producer in ArtifactProducer::all() {
        assert_eq!(
            ArtifactProducer::from_str(producer.as_str()),
            Some(producer)
        );
    }

    assert_eq!(ArtifactProducer::from_str("unknown"), None);
}
