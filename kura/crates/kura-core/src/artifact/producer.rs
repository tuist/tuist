use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ArtifactProducer {
    Xcode,
    Gradle,
    Module,
    Reapi,
    Nx,
    Metro,
}

impl ArtifactProducer {
    #[cfg(test)]
    pub const fn all() -> [Self; 6] {
        [
            Self::Xcode,
            Self::Gradle,
            Self::Module,
            Self::Reapi,
            Self::Nx,
            Self::Metro,
        ]
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Xcode => "xcode",
            Self::Gradle => "gradle",
            Self::Module => "module",
            Self::Reapi => "reapi",
            Self::Nx => "nx",
            Self::Metro => "metro",
        }
    }

    pub fn from_str(value: &str) -> Option<Self> {
        match value {
            "xcode" => Some(Self::Xcode),
            "gradle" => Some(Self::Gradle),
            "module" => Some(Self::Module),
            "reapi" => Some(Self::Reapi),
            "nx" => Some(Self::Nx),
            "metro" => Some(Self::Metro),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
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
}
