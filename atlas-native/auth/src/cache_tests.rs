use super::*;
use crate::tests::{TestDirectory, registration};

fn session() -> Session {
    crate::bootstrap(Session {
        registration: registration(),
        access_token: "access".into(),
        refresh_token: "refresh".into(),
        expires_at: now() + 3600,
        cache_id: None,
    })
    .unwrap()
}

#[test]
fn snapshots_survive_reopen_and_migrations_preserve_their_contents() {
    let directory = TestDirectory::new();
    let session = session();
    let cache = Cache::open(directory.as_str(), &session).unwrap();
    cache.write("orbit/active", "saved rows", cache.generation().unwrap());
    drop(cache);
    let mut connection = Connection::open(directory.path().join("reads.sqlite3")).unwrap();
    let migrations = [
        MIGRATIONS[0],
        "ALTER TABLE read_snapshots ADD COLUMN etag TEXT;",
    ];
    migrate(&mut connection, &migrations).unwrap();
    migrate(&mut connection, &migrations).unwrap();
    assert_eq!(
        connection
            .query_row("SELECT payload FROM read_snapshots", [], |row| row
                .get::<_, String>(0))
            .unwrap(),
        "saved rows"
    );
    assert_eq!(
        connection
            .pragma_query_value(None, "user_version", |row| row.get::<_, u32>(0))
            .unwrap(),
        2
    );
    drop(connection);
    // An older binary refuses the new schema without deleting cached rows.
    let before = std::fs::read(directory.path().join("reads.sqlite3")).unwrap();
    assert!(Cache::open(directory.as_str(), &session).is_none());
    assert_eq!(
        std::fs::read(directory.path().join("reads.sqlite3")).unwrap(),
        before
    );
    let mut connection = Connection::open(directory.path().join("reads.sqlite3")).unwrap();
    assert_eq!(
        connection
            .query_row("SELECT payload FROM read_snapshots", [], |row| row
                .get::<_, String>(0))
            .unwrap(),
        "saved rows"
    );
    assert!(migrate(&mut connection, MIGRATIONS).is_err());
}

#[test]
fn failed_upgrade_rolls_back_ddl_data_and_schema_version() {
    let mut connection = Connection::open_in_memory().unwrap();
    migrate(&mut connection, MIGRATIONS).unwrap();
    let migrations = [
        MIGRATIONS[0],
        "INSERT INTO cache_namespaces (id) VALUES ('migration-data'); CREATE TABLE pending_change (id INTEGER);",
        "INSERT INTO missing_table VALUES (1);",
    ];
    assert!(migrate(&mut connection, &migrations).is_err());
    assert_eq!(
        connection
            .pragma_query_value(None, "user_version", |row| row.get::<_, u32>(0))
            .unwrap(),
        1
    );
    assert_eq!(
        connection
            .query_row("SELECT count(*) FROM cache_namespaces", [], |row| row
                .get::<_, u32>(0))
            .unwrap(),
        0
    );
    assert!(connection.prepare("SELECT * FROM pending_change").is_err());
    migrate(&mut connection, &migrations[..2]).unwrap();
    assert_eq!(
        connection
            .query_row("SELECT id FROM cache_namespaces", [], |row| row
                .get::<_, String>(0))
            .unwrap(),
        "migration-data"
    );
}

#[test]
fn scopes_queries_and_invalidations_fence_late_writes_across_restarts() {
    let directory = TestDirectory::new();
    let first_session = session();
    let cache = Cache::open(directory.as_str(), &first_session).unwrap();
    let generation = cache.generation().unwrap();
    cache.write("active", "first", generation);
    cache.write("archived", "other query", generation);
    let second = Cache::open(directory.as_str(), &session()).unwrap();
    assert!(second.read("active").is_none());
    let mut other_origin = first_session.clone();
    other_origin.registration.server = "https://another.example/".into();
    assert!(
        Cache::open(directory.as_str(), &other_origin)
            .unwrap()
            .read("active")
            .is_none()
    );
    drop(cache);
    let cache = Cache::open(directory.as_str(), &first_session).unwrap();
    assert_eq!(cache.read("active").as_deref(), Some("first"));
    assert_eq!(cache.read("archived").as_deref(), Some("other query"));
    cache.invalidate(false);
    cache.write("active", "pre-mutation result", generation);
    assert!(cache.read("active").is_none());
    assert!(cache.read("archived").is_none());
    cache.write("active", "new result", cache.generation().unwrap());
    assert_eq!(cache.read("active").as_deref(), Some("new result"));
    cache.invalidate(true);
    cache.write("active", "late logout result", generation + 1);
    drop(cache);
    let cache = Cache::open(directory.as_str(), &first_session).unwrap();
    assert!(cache.generation().is_none());
    assert!(cache.read("active").is_none());
}

#[test]
fn retention_and_size_limits_do_not_turn_bad_storage_into_an_app_failure() {
    let directory = TestDirectory::new();
    let session = session();
    let cache = Cache::open(directory.as_str(), &session).unwrap();
    let generation = cache.generation().unwrap();
    cache.write("oversized", &"x".repeat(MAX_BYTES + 1), generation);
    assert!(cache.read("oversized").is_none());
    for index in 0..MAX_ENTRIES + 1 {
        cache.write(&format!("key-{index}"), "rows", generation);
    }
    assert!(cache.read("key-0").is_none());
    assert_eq!(
        cache.read(&format!("key-{MAX_ENTRIES}")).as_deref(),
        Some("rows")
    );
    cache
        .database
        .lock()
        .unwrap()
        .execute(
            "UPDATE read_snapshots SET fetched_at = ?1",
            [(now() - RETENTION - 1) as i64],
        )
        .unwrap();
    assert!(cache.read("key-1").is_none());
    drop(cache);
    std::fs::write(directory.path().join("reads.sqlite3"), b"not a database").unwrap();
    assert!(Cache::open(directory.as_str(), &session).is_none());
}

#[test]
fn local_read_surfaces_strip_write_authority_and_automation_payloads() {
    let directory = TestDirectory::new();
    let session = session();
    let cache = Cache::open(directory.as_str(), &session).unwrap();
    let business = json!({"surface":"business_list","resource":"accounts","page":1,"query":"Acme","filters":{}});
    let record = json!({"id":"01922cc0-0000-7000-8000-000000000001","fields":{"name":"Acme"},"can_edit":true,"can_delete":true});
    let request: Read = serde_json::from_value(business.clone()).unwrap();
    cache.write(
        &request.key().unwrap(),
        &json!({"items":[record],"can_write":true,"options":{"users":["private-option"]}})
            .to_string(),
        cache.generation().unwrap(),
    );
    let value = read(session.clone(), directory.as_str(), request, true).unwrap()["value"].clone();
    assert_eq!(value["items"][0]["fields"]["name"], "Acme");
    assert_eq!(value["can_write"], false);
    assert_eq!(value["items"][0]["can_edit"], false);
    assert_eq!(value["items"][0]["can_delete"], false);
    assert!(!value.to_string().contains("private-option"));
    assert_eq!(value["cached"], true);
    for kind in ["workflow", "execution", "approval"] {
        let request: Read = serde_json::from_value(json!({"surface":"automation_record","kind":kind,"id":"01922cc0-0000-7000-8000-000000000001"})).unwrap();
        let key = request.key().unwrap();
        let response = json!({"id":"01922cc0-0000-7000-8000-000000000001","name":"Review release","can_run":true,"can_control":true,"can_decide":true,"revision_id":"authority","input_schema":{"secret":"input"},"payload_json":"private approval","payload_digest":"decision authority","outputs_json":"protected result","steps":[{"step_id":"inspect","status":"running","input":"private"}]});
        let fresh = read_using(
            session.clone(),
            directory.as_str(),
            request,
            false,
            |_, _| Ok(response.clone()),
        )
        .unwrap();
        assert_eq!(fresh["value"], response);
        // Inspect the stored payload before the local-read sanitizer runs again.
        let persisted = cache.read(&key).unwrap();
        for secret in [
            "authority",
            "private",
            "protected result",
            "input_schema",
            "payload_digest",
            "can_run",
            "can_control",
            "can_decide",
        ] {
            assert!(!persisted.contains(secret), "Persisted {secret}");
        }
        let request: Read = serde_json::from_value(json!({"surface":"automation_record","kind":kind,"id":"01922cc0-0000-7000-8000-000000000001"})).unwrap();
        let value =
            read(session.clone(), directory.as_str(), request, true).unwrap()["value"].clone();
        assert_eq!(value["name"], "Review release");
        assert_eq!(value["steps"][0]["status"], "running");
        assert_eq!(value["cached"], true);
        for field in [
            "can_run",
            "can_control",
            "can_decide",
            "revision_id",
            "input_schema",
            "payload_json",
            "payload_digest",
            "outputs_json",
        ] {
            assert!(value.get(field).is_none(), "{field}");
        }
        assert!(value["steps"][0].get("input").is_none());
    }
    let mut other = business;
    other["query"] = json!("Other search");
    assert!(
        read(
            session,
            directory.as_str(),
            serde_json::from_value(other).unwrap(),
            true
        )
        .unwrap()["value"]
            .is_null()
    );
}
