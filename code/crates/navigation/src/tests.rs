use super::*;
use url::Url;

fn server() -> Url {
    Url::parse("https://tuist.dev").unwrap()
}

#[test]
fn shares_the_mobile_route_contract() {
    // Keep this compile input local so Once fingerprints and materializes it.
    // mise run test checks parity with the canonical mobile fixture first.
    let fixtures: serde_json::Value = serde_json::from_str(include_str!("routes.json")).unwrap();
    for fixture in fixtures["previews"].as_array().unwrap() {
        let server = Url::parse(fixture["server"].as_str().unwrap()).unwrap();
        let route = Route::Preview(Preview {
            account: fixture["account"].as_str().unwrap().into(),
            project: fixture["project"].as_str().unwrap().into(),
            id: fixture["id"].as_str().unwrap().into(),
        });
        let canonical = fixture["canonical"].as_str().unwrap();
        let handoff = fixture["handoff"].as_str().unwrap();
        assert_eq!(route.url(&server).unwrap().as_str(), canonical);
        assert_eq!(route.handoff_url(&server).unwrap().as_str(), handoff);
        assert_eq!(Route::parse(canonical, &server), Ok(route.clone()));
        assert_eq!(Route::parse(handoff, &server), Ok(route));
    }
    for value in fixtures["web_only"].as_array().unwrap() {
        let value = value.as_str().unwrap();
        assert!(Route::parse(value, &server()).is_err(), "{value}");
        assert!(Route::is_server_web_url(value, &server()), "{value}");
    }
}

#[test]
fn rejects_invalid_destinations_without_url_normalization_hiding_them() {
    for value in [
        "tuist://app/profile?",
        "tuist://app/previews/",
        "tuist://app/profile#",
        "tuist://@app/profile",
        "tuist://app:443/profile",
        "tuist://app//profile",
        "tuist://app/a/p/previews/latest",
        "tuist://app/a/p/previews/id/extra",
        "tuist://app/a/p/previews/id?server=https://tuist.dev&server=https://tuist.dev",
        "tuist://app/a/p/previews/id?unknown=1",
        "tuist://app/a/p/previews/id?server=",
        "https://tuist.dev/a/p/previews/id?",
        "https://tuist.dev:0/a/p/previews/id",
        "https://tuist.dev/a/../p/previews/id",
        "tuist://app/a/p/previews/%",
        "https://tuist.dev/a/p/previews/id#fragment",
    ] {
        assert!(Route::parse(value, &server()).is_err(), "{value}");
    }
    for segment in [
        "", ".", "..", "%2E", "%2e%2e", "%2F", "%5C", "%00", "%20", "%C2%A0", "%FF", "%0a",
    ] {
        for path in [
            format!("{segment}/p/previews/id"),
            format!("a/{segment}/previews/id"),
            format!("a/p/previews/{segment}"),
        ] {
            for origin in ["tuist://app", "https://tuist.dev"] {
                let value = format!("{origin}/{path}");
                assert!(Route::parse(&value, &server()).is_err(), "{value}");
            }
        }
    }
}

#[test]
fn matches_the_full_server_base_and_legacy_alias_defaults_to_production() {
    let staging = Url::parse("https://staging.tuist.dev/base/").unwrap();
    assert_eq!(
        Route::parse("tuist://app/a/p/previews/id", &staging),
        Err(RouteError::DifferentServer)
    );
    for value in [
        "http://staging.tuist.dev/base/a/p/previews/id",
        "https://staging.tuist.dev:8443/base/a/p/previews/id",
        "https://staging.tuist.dev/baseball/a/p/previews/id",
    ] {
        assert!(Route::parse(value, &staging).is_err());
        assert!(!Route::is_server_web_url(value, &staging));
    }
    assert!(
        Route::parse(
            "https://STAGING.tuist.dev:443/base/a/p/previews/id",
            &staging
        )
        .is_ok()
    );
    assert_eq!(
        Route::parse("tuist://app/profile", &staging),
        Ok(Route::Profile)
    );
    assert_eq!(
        Route::Profile.url(&staging).unwrap().as_str(),
        "tuist://app/profile"
    );
}

#[test]
fn pending_links_wait_for_authentication_and_oauth_does_not_replace_them() {
    let mut nav = Navigation::default();
    nav.receive("tuist://app/profile", &server());
    assert_eq!(nav.tab, Tab::Previews);
    nav.receive("tuist://app/a/p/previews/first", &server());
    nav.receive("tuist://oauth-callback?code=secret", &server());
    nav.resume();
    assert_eq!(nav.preview.as_ref().unwrap().id, "first");
    nav.receive("tuist://app/a/p/previews/second", &server());
    nav.resume();
    nav.receive("tuist://app/a/p/previews/second", &server());
    nav.resume();
    assert_eq!(nav.preview.as_ref().unwrap().id, "second");
    nav.receive("https://wrong.example/a/p/previews/third", &server());
    nav.resume();
    assert_eq!(nav.preview.as_ref().unwrap().id, "second");
    assert_eq!(nav.error, Some(RouteError::DifferentServer));
    nav.navigate(Route::Profile);
    assert_eq!(nav.preview.as_ref().unwrap().id, "second");
    nav.receive("tuist://app/previews", &server());
    nav.resume();
    assert_eq!(nav.tab, Tab::Previews);
    assert_eq!(nav.preview, None);
    nav.navigate(Route::Profile);
    nav.resume();
    assert_eq!(nav.tab, Tab::Profile);
}
