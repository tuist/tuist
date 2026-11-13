use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use sha2::{Digest, Sha256};

/// One sign-in's PKCE verifier (RFC 7636, S256) and anti-forgery state.
#[derive(Debug, Clone)]
pub struct Pkce {
    pub verifier: String,
    pub challenge: String,
    pub state: String,
}

impl Pkce {
    pub fn generate() -> Self {
        let verifier = random_token(32);
        Self {
            challenge: challenge(&verifier),
            verifier,
            state: random_token(16),
        }
    }
}

fn random_token(bytes: usize) -> String {
    let mut buffer = vec![0; bytes];
    getrandom::fill(&mut buffer).expect("the operating system provides randomness");
    URL_SAFE_NO_PAD.encode(buffer)
}

fn challenge(verifier: &str) -> String {
    URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn challenge_matches_rfc_7636_appendix_b() {
        assert_eq!(
            challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        );
    }

    #[test]
    fn each_sign_in_gets_fresh_values() {
        let (first, second) = (Pkce::generate(), Pkce::generate());
        assert_ne!(first.verifier, second.verifier);
        assert_ne!(first.state, second.state);
        assert_eq!(first.verifier.len(), 43);
    }
}
