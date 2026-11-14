//! Reads the claims Tuist clients rely on from a JWT payload. Signatures are
//! not verified: the server is the authority, and clients only need expiry,
//! token type, and the account shown in the UI.

use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde::Deserialize;

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct Claims {
    /// Expiry as Unix seconds.
    pub exp: i64,
    pub sub: Option<String>,
    /// OAuth subjects identify accounts; this claim identifies the issuing user.
    pub user_id: Option<u64>,
    pub email: Option<String>,
    pub preferred_username: Option<String>,
    /// `account` for tokens minted by the OAuth authorization server; other or
    /// absent values are legacy user tokens refreshed through the API.
    #[serde(rename = "type")]
    pub kind: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InvalidJwt;

impl std::fmt::Display for InvalidJwt {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("the token is not a valid JWT")
    }
}

impl std::error::Error for InvalidJwt {}

impl Claims {
    pub fn parse(token: &str) -> Result<Self, InvalidJwt> {
        let mut parts = token.split('.');
        let (Some(_), Some(payload), Some(_), None) =
            (parts.next(), parts.next(), parts.next(), parts.next())
        else {
            return Err(InvalidJwt);
        };
        // Accept padded payloads too, as Foundation's decoder does.
        let bytes = URL_SAFE_NO_PAD
            .decode(payload.trim_end_matches('='))
            .map_err(|_| InvalidJwt)?;
        serde_json::from_slice(&bytes).map_err(|_| InvalidJwt)
    }

    pub fn is_account_token(&self) -> bool {
        self.kind.as_deref() == Some("account")
    }

    /// Guardian uses user subjects for legacy tokens and account subjects for
    /// OAuth tokens. Match the issuing user across both without conflating
    /// unrelated users/accounts that happen to share a numeric database ID.
    pub fn identity(&self) -> Option<String> {
        if self.is_account_token()
            && let Some(user_id) = self.user_id
        {
            return Some(format!("user:{user_id}"));
        }
        match &self.sub {
            Some(sub) => (!sub.is_empty()).then(|| {
                let namespace = if self.is_account_token() {
                    "sub"
                } else {
                    "user"
                };
                format!("{namespace}:{sub}")
            }),
            None => self
                .preferred_username
                .as_ref()
                .filter(|name| !name.is_empty())
                .map(|name| format!("username:{name}")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_claims_from_payload() {
        // Payload: {"exp":1700000000,"email":"a@b.c","preferred_username":"ana","type":"account"}
        let token = "eyJhbGciOiJub25lIn0.eyJleHAiOjE3MDAwMDAwMDAsImVtYWlsIjoiYUBiLmMiLCJwcmVmZXJyZWRfdXNlcm5hbWUiOiJhbmEiLCJ0eXBlIjoiYWNjb3VudCJ9.";
        let claims = Claims::parse(token).unwrap();
        assert_eq!(claims.exp, 1_700_000_000);
        assert_eq!(claims.email.as_deref(), Some("a@b.c"));
        assert_eq!(claims.preferred_username.as_deref(), Some("ana"));
        assert!(claims.is_account_token());
    }

    #[test]
    fn rejects_tokens_without_three_segments() {
        assert_eq!(Claims::parse("a.b"), Err(InvalidJwt));
        assert_eq!(Claims::parse("a.b.c.d"), Err(InvalidJwt));
    }

    #[test]
    fn identity_prefers_subject_and_only_falls_back_for_legacy_tokens() {
        let mut claims = Claims {
            exp: 1,
            sub: Some("123".into()),
            user_id: None,
            email: None,
            preferred_username: Some("ana".into()),
            kind: None,
        };
        assert_eq!(claims.identity().as_deref(), Some("user:123"));
        claims.preferred_username = Some("renamed".into());
        assert_eq!(claims.identity().as_deref(), Some("user:123"));
        claims.kind = Some("account".into());
        assert_eq!(claims.identity().as_deref(), Some("sub:123"));
        claims.user_id = Some(456);
        assert_eq!(claims.identity().as_deref(), Some("user:456"));
        claims.sub = Some("999".into());
        claims.user_id = Some(123);
        assert_eq!(claims.identity().as_deref(), Some("user:123"));
        claims.user_id = None;
        claims.sub = None;
        assert_eq!(claims.identity().as_deref(), Some("username:renamed"));
        claims.sub = Some(String::new());
        assert!(claims.identity().is_none());
    }
}
