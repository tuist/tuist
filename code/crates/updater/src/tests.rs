//! Exercises public check/download/install with fresh, disposable signing keys.
//! Runtime discovery, transport destinations, precommit faults and process launch
//! are injected; authentication, parsing, verification and file replacement are real.

use super::*;
use minisign::KeyPair;
use serde_json::{Value, json};
use std::{
    cell::RefCell,
    io::{BufRead, BufReader, Write},
    net::{TcpListener, TcpStream},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread::{self, JoinHandle},
};

thread_local! {
    pub(super) static RUNTIME: RefCell<Option<Runtime>> = const { RefCell::new(None) };
}

#[cfg(unix)]
type BeforeCommit = Box<dyn Fn(&std::path::Path, &std::path::Path) -> Result<()>>;
#[cfg(unix)]
type Restart = Box<dyn Fn(&mut std::process::Command) -> Result<()>>;
#[cfg(unix)]
thread_local! {
    pub(super) static BEFORE_COMMIT: RefCell<Option<BeforeCommit>> = const { RefCell::new(None) };
    pub(super) static RESTART: RefCell<Option<Restart>> = const { RefCell::new(None) };
}

struct Server {
    origin: String,
    stop: Arc<AtomicBool>,
    requests: Arc<Mutex<Vec<String>>>,
    worker: Option<JoinHandle<()>>,
}

impl Server {
    fn new(
        manifest: Vec<u8>,
        signature: Vec<u8>,
        payload: Vec<u8>,
        payload_length: Option<u64>,
        chunked_manifest: bool,
    ) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let origin = format!("http://{}", listener.local_addr().unwrap());
        let stop = Arc::new(AtomicBool::new(false));
        let requests = Arc::new(Mutex::new(Vec::new()));
        let stopped = stop.clone();
        let seen = requests.clone();
        let worker = thread::spawn(move || {
            for incoming in listener.incoming() {
                if stopped.load(Ordering::Relaxed) {
                    break;
                }
                let mut stream = incoming.unwrap();
                stream
                    .set_read_timeout(Some(Duration::from_secs(3)))
                    .unwrap();
                let mut reader = BufReader::new(&stream);
                let mut request = String::new();
                reader.read_line(&mut request).unwrap();
                let path = request.split_whitespace().nth(1).unwrap().to_owned();
                loop {
                    let mut header = String::new();
                    reader.read_line(&mut header).unwrap();
                    if header == "\r\n" || header.is_empty() {
                        break;
                    }
                }
                seen.lock().unwrap().push(path.clone());
                let body = match path.as_str() {
                    "/latest.json" => &manifest,
                    "/latest.json.sig" => &signature,
                    "/payload" => &payload,
                    _ => panic!("Unexpected updater request {path}"),
                };
                // A body without Content-Length exercises the streaming metadata
                // bound as well as the advertised-size check.
                if path == "/latest.json" && chunked_manifest {
                    write!(stream, "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n").unwrap();
                } else {
                    let length = if path == "/payload" {
                        payload_length.unwrap_or(body.len() as u64)
                    } else {
                        body.len() as u64
                    };
                    write!(
                        stream,
                        "HTTP/1.1 200 OK\r\nContent-Length: {length}\r\nConnection: close\r\n\r\n"
                    )
                    .unwrap();
                }
                // The client intentionally closes early on over-limit responses.
                let _ = stream.write_all(body);
            }
        });
        Self {
            origin,
            stop,
            requests,
            worker: Some(worker),
        }
    }
}

impl Drop for Server {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        let _ = TcpStream::connect(self.origin.trim_start_matches("http://"));
        self.worker.take().unwrap().join().unwrap();
    }
}

struct Fixture {
    server: Server,
    installation: tempfile::TempDir,
}

impl Fixture {
    #[allow(clippy::too_many_arguments)] // Explicit adversarial transport settings.
    fn new(
        key: &KeyPair,
        manifest: Vec<u8>,
        signature: Vec<u8>,
        payload: Vec<u8>,
        target: &'static str,
        payload_length: Option<u64>,
        chunked: bool,
    ) -> Self {
        let server = Server::new(manifest, signature, payload, payload_length, chunked);
        let installation = tempfile::tempdir().unwrap();
        let path = installation.path().join("TuistCode.AppImage");
        std::fs::write(&path, b"unchanged installation").unwrap();
        RUNTIME.with(|slot| {
            slot.replace(Some(Runtime {
                key: public_key(key),
                target,
                path,
                feed: format!("{}/latest.json", server.origin),
                payload_endpoint: Some(format!("{}/payload", server.origin).parse().unwrap()),
            }))
        });
        Self {
            server,
            installation,
        }
    }

    fn assert_unmodified(&self) {
        assert_eq!(
            std::fs::read(self.installation.path().join("TuistCode.AppImage")).unwrap(),
            b"unchanged installation"
        );
        assert_eq!(
            std::fs::read_dir(self.installation.path()).unwrap().count(),
            1
        );
    }

    fn assert_requests(&self, expected: &[&str]) {
        assert_eq!(*self.server.requests.lock().unwrap(), expected);
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        RUNTIME.with(|slot| slot.replace(None));
        #[cfg(unix)]
        {
            BEFORE_COMMIT.with(|slot| slot.replace(None));
            RESTART.with(|slot| slot.replace(None));
        }
    }
}

fn keypair() -> KeyPair {
    KeyPair::generate_unencrypted_keypair().unwrap()
}
fn public_key(key: &KeyPair) -> String {
    STANDARD.encode(key.pk.to_box().unwrap().to_bytes())
}
fn sign(key: &KeyPair, bytes: &[u8]) -> Vec<u8> {
    STANDARD
        .encode(
            minisign::sign(
                Some(&key.pk),
                &key.sk,
                bytes,
                Some("ephemeral test only"),
                None,
            )
            .unwrap()
            .to_string(),
        )
        .into_bytes()
}

fn manifest(key: &KeyPair, version: &str) -> Value {
    json!({
        "version": version,
        "notes": "Authenticated release notes",
        "platforms": {
            "linux-x86_64": {
                "url": format!("https://github.com/tuist/tuist/releases/download/desktop@{version}/TuistCode_x86_64.AppImage"),
                "signature": String::from_utf8(sign(key, b"signed package")).unwrap(),
                "format": "appimage"
            },
            "windows-x86_64": {
                "url": format!("https://github.com/tuist/tuist/releases/download/desktop@{version}/TuistCode_x64-setup.exe"),
                "signature": String::from_utf8(sign(key, b"signed package")).unwrap(),
                "format": "nsis"
            }
        }
    })
}

fn signed_fixture(key: &KeyPair, value: Value, payload: &[u8], target: &'static str) -> Fixture {
    let bytes = serde_json::to_vec(&value).unwrap();
    let signature = sign(key, &bytes);
    Fixture::new(key, bytes, signature, payload.to_vec(), target, None, false)
}

#[test]
fn development_build_is_disabled_without_network_or_installation() {
    if PUBLIC_KEY.trim().is_empty() {
        assert!(
            availability()
                .unwrap_err()
                .contains("no release verification key")
        );
        assert!(check().is_err());
    }
}

#[test]
fn signed_manifest_and_payload_prepare_without_installing_on_both_targets() {
    let key = keypair();
    for target in ["linux-x86_64", "windows-x86_64"] {
        let fixture = signed_fixture(&key, manifest(&key, "99.0.0"), b"signed package", target);
        assert!(availability().is_ok());
        let update = check().unwrap().unwrap();
        assert_eq!(update.version(), "99.0.0");
        assert_eq!(update.notes(), Some("Authenticated release notes"));
        fixture.assert_unmodified();
        let prepared = update.download().unwrap();
        fixture.assert_unmodified();
        drop(prepared); // Cancel, never call a real installer in tests.
        fixture.assert_unmodified();
        fixture.assert_requests(&["/latest.json", "/latest.json.sig", "/payload"]);
    }
}

#[test]
fn wrong_key_tampered_and_unsigned_manifests_fail_before_parsing() {
    let key = keypair();
    let bytes = serde_json::to_vec(&manifest(&key, "99.0.0")).unwrap();
    let wrong = keypair();
    let scenarios = [
        (bytes.clone(), sign(&wrong, &bytes)),
        (b"not even valid json".to_vec(), sign(&key, &bytes)),
        (bytes, Vec::new()),
    ];
    for (bytes, signature) in scenarios {
        let fixture = Fixture::new(
            &key,
            bytes,
            signature,
            Vec::new(),
            "linux-x86_64",
            None,
            false,
        );
        let error = check().err().unwrap();
        assert!(!format!("{error:#}").contains("Invalid signed release manifest"));
        fixture.assert_unmodified();
        fixture.assert_requests(&["/latest.json", "/latest.json.sig"]);
    }
}

#[test]
fn tampered_or_wrong_key_payload_is_never_prepared() {
    let key = keypair();
    let wrong = keypair();
    for (value, payload) in [
        (manifest(&key, "99.0.0"), b"tampered package".as_slice()),
        (manifest(&wrong, "99.0.0"), b"signed package".as_slice()),
    ] {
        // The outer manifest is authentic even when its payload signature is bad.
        let fixture = signed_fixture(&key, value, payload, "linux-x86_64");
        assert!(check().unwrap().unwrap().download().is_err());
        fixture.assert_unmodified();
    }
}

#[test]
fn wrong_target_format_dynamic_and_unsigned_payload_are_rejected() {
    let key = keypair();
    for kind in ["target", "format", "dynamic", "unsigned"] {
        let mut value = manifest(&key, "99.0.0");
        match kind {
            "target" => {
                value["platforms"]
                    .as_object_mut()
                    .unwrap()
                    .remove("linux-x86_64");
            }
            "format" => value["platforms"]["linux-x86_64"]["format"] = json!("nsis"),
            "dynamic" => {
                let entry = value["platforms"]["linux-x86_64"].clone();
                value.as_object_mut().unwrap().remove("platforms");
                value
                    .as_object_mut()
                    .unwrap()
                    .extend(entry.as_object().unwrap().clone());
            }
            "unsigned" => value["platforms"]["linux-x86_64"]["signature"] = json!(""),
            _ => unreachable!(),
        }
        let fixture = signed_fixture(&key, value, b"signed package", "linux-x86_64");
        assert!(check().is_err(), "Accepted {kind}");
        fixture.assert_unmodified();
        fixture.assert_requests(&["/latest.json", "/latest.json.sig"]);
    }
}

#[test]
fn nonnewer_stable_versions_return_none_and_prereleases_are_rejected() {
    let key = keypair();
    for version in [
        env!("CARGO_PKG_VERSION"),
        "0.0.0",
        "99.0.0-beta.1",
        "99.0.0+build",
    ] {
        let fixture = signed_fixture(
            &key,
            manifest(&key, version),
            b"signed package",
            "linux-x86_64",
        );
        if version.contains(['-', '+']) {
            assert!(check().is_err());
        } else {
            assert!(check().unwrap().is_none());
        }
        fixture.assert_unmodified();
        fixture.assert_requests(&["/latest.json", "/latest.json.sig"]);
    }
}

#[test]
fn signed_but_nonimmutable_or_mismatched_urls_are_rejected() {
    let key = keypair();
    for url in [
        "http://github.com/tuist/tuist/releases/download/desktop@99.0.0/TuistCode.AppImage",
        "https://example.com/tuist/tuist/releases/download/desktop@99.0.0/TuistCode.AppImage",
        "https://github.com/other/tuist/releases/download/desktop@99.0.0/TuistCode.AppImage",
        "https://github.com/tuist/tuist/releases/download/desktop@98.0.0/TuistCode.AppImage",
        "https://github.com/tuist/tuist/releases/download/desktop-updates/TuistCode.AppImage",
        "https://user:password@github.com/tuist/tuist/releases/download/desktop@99.0.0/TuistCode.AppImage",
        "https://github.com/tuist/tuist/releases/download/desktop@99.0.0/TuistCode.AppImage?token=x",
        "https://github.com/tuist/tuist/releases/download/desktop@99.0.0/TuistCode.AppImage#fragment",
        "https://github.com/tuist/tuist/releases/download/desktop@99.0.0/nested/TuistCode.AppImage",
        "https://github.com/tuist/tuist/releases/download/desktop@99.0.0/TuistCode.exe",
        "https://github.com/tuist/tuist/releases/download/desktop@99.0.0/TuistCode.AppImage.tar.gz",
    ] {
        let mut value = manifest(&key, "99.0.0");
        value["platforms"]["linux-x86_64"]["url"] = json!(url);
        let fixture = signed_fixture(&key, value, b"signed package", "linux-x86_64");
        assert!(check().is_err(), "Accepted {url}");
        fixture.assert_unmodified();
    }
}

#[test]
fn metadata_bounds_cover_advertised_and_streamed_sizes() {
    let key = keypair();
    for chunked in [false, true] {
        let fixture = Fixture::new(
            &key,
            vec![b'x'; MANIFEST_LIMIT as usize + 1],
            Vec::new(),
            Vec::new(),
            "linux-x86_64",
            None,
            chunked,
        );
        assert!(format!("{:#}", check().err().unwrap()).contains("size limit"));
        fixture.assert_requests(&["/latest.json"]);
        fixture.assert_unmodified();
    }
    let bytes = serde_json::to_vec(&manifest(&key, "99.0.0")).unwrap();
    let fixture = Fixture::new(
        &key,
        bytes,
        vec![b'x'; SIGNATURE_LIMIT as usize + 1],
        Vec::new(),
        "linux-x86_64",
        None,
        false,
    );
    assert!(format!("{:#}", check().err().unwrap()).contains("size limit"));
    fixture.assert_unmodified();
}

#[test]
fn oversized_payload_is_interrupted_before_allocating_advertised_size() {
    let key = keypair();
    let bytes = serde_json::to_vec(&manifest(&key, "99.0.0")).unwrap();
    let signature = sign(&key, &bytes);
    let fixture = Fixture::new(
        &key,
        bytes,
        signature,
        b"x".to_vec(),
        "linux-x86_64",
        Some(PAYLOAD_LIMIT + 1),
        false,
    );
    let error = check().unwrap().unwrap().download().err().unwrap();
    assert!(format!("{error:#}").contains("size limit"));
    fixture.assert_unmodified();
}

#[test]
fn installation_changed_after_download_is_rejected_without_side_effects() {
    let key = keypair();
    let fixture = signed_fixture(
        &key,
        manifest(&key, "99.0.0"),
        b"signed package",
        "linux-x86_64",
    );
    let prepared = check().unwrap().unwrap().download().unwrap();
    RUNTIME.with(|slot| {
        slot.borrow_mut().as_mut().unwrap().path = fixture.installation.path().join("moved")
    });
    assert!(prepared.install_and_restart().is_err());
    fixture.assert_unmodified();
}

#[cfg(unix)]
#[test]
fn public_install_atomically_replaces_verified_bytes_and_preserves_permissions() {
    use std::os::unix::fs::{MetadataExt, PermissionsExt};
    use std::rc::Rc;

    let key = keypair();
    let fixture = signed_fixture(
        &key,
        manifest(&key, "99.0.0"),
        b"signed package",
        "linux-x86_64",
    );
    let path = fixture.installation.path().join("TuistCode.AppImage");
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o751)).unwrap();
    let mut old_executable = std::fs::File::open(&path).unwrap();
    let old_inode = old_executable.metadata().unwrap().ino();
    let staged_seen = Rc::new(std::cell::Cell::new(false));
    let seen = staged_seen.clone();
    BEFORE_COMMIT.with(|slot| {
        slot.replace(Some(Box::new(move |path, staged| {
            assert_eq!(path.parent(), staged.parent());
            assert_eq!(std::fs::read(path)?, b"unchanged installation");
            assert_eq!(std::fs::metadata(path)?.ino(), old_inode);
            assert_eq!(std::fs::read(staged)?, b"signed package");
            assert_eq!(
                std::fs::metadata(staged)?.permissions().mode() & 0o7777,
                0o751
            );
            seen.set(true);
            Ok(())
        })));
    });
    let restarted = Rc::new(std::cell::Cell::new(false));
    let seen = restarted.clone();
    let restart_path = path.clone();
    RESTART.with(|slot| {
        slot.replace(Some(Box::new(move |command| {
            assert_eq!(command.get_program(), restart_path.as_os_str());
            assert_eq!(command.get_args().count(), 0);
            assert_eq!(std::fs::read(&restart_path)?, b"signed package");
            seen.set(true);
            Ok(())
        })));
    });
    check()
        .unwrap()
        .unwrap()
        .download()
        .unwrap()
        .install_and_restart()
        .unwrap();
    assert!(staged_seen.get());
    assert!(restarted.get());
    let mut retained_bytes = Vec::new();
    old_executable.read_to_end(&mut retained_bytes).unwrap();
    assert_eq!(retained_bytes, b"unchanged installation");
    assert_eq!(std::fs::read(&path).unwrap(), b"signed package");
    assert_ne!(std::fs::metadata(&path).unwrap().ino(), old_inode);
    assert_eq!(
        std::fs::metadata(path).unwrap().permissions().mode() & 0o7777,
        0o751
    );
    assert_eq!(
        std::fs::read_dir(fixture.installation.path())
            .unwrap()
            .count(),
        1
    );
}

#[cfg(unix)]
#[test]
fn public_install_preserves_old_executable_on_precommit_and_rename_failures() {
    let key = keypair();
    for fail_rename in [false, true] {
        let fixture = signed_fixture(
            &key,
            manifest(&key, "99.0.0"),
            b"signed package",
            "linux-x86_64",
        );
        BEFORE_COMMIT.with(|slot| {
            slot.replace(Some(Box::new(move |path, staged| {
                assert_eq!(std::fs::read(path)?, b"unchanged installation");
                assert_eq!(std::fs::read(staged)?, b"signed package");
                if fail_rename {
                    // Cause the real atomic rename to fail, not a fake installer.
                    std::fs::remove_file(staged)?;
                    Ok(())
                } else {
                    Err(std::io::Error::other("interrupted before commit").into())
                }
            })));
        });
        RESTART.with(|slot| {
            slot.replace(Some(Box::new(|_| {
                panic!("Must not restart a failed install")
            })));
        });
        let error = check()
            .unwrap()
            .unwrap()
            .download()
            .unwrap()
            .install_and_restart()
            .unwrap_err();
        assert!(format!("{error:#}").contains("Failed to install update"));
        fixture.assert_unmodified(); // Also proves temporary files are cleaned up.
    }
}

#[cfg(unix)]
#[test]
fn restart_preserves_fuseless_mode_and_removes_stale_mount_environment() {
    for original in [None, Some("/user/libraries"), Some("")] {
        let mut environment = vec![
            ("APPIMAGE", "/old/TuistCode.AppImage"),
            ("APPDIR", "/tmp/.mount_old"),
            ("ARGV0", "/old/TuistCode.AppImage"),
            ("OWD", "/old/working-directory"),
            ("APPIMAGE_SILENT_INSTALL", "1"),
            ("APPIMAGE_EXTRACT_AND_RUN", "1"),
            ("LD_LIBRARY_PATH", "/tmp/.mount_old/usr/lib"),
            ("HOME", "/user/home"),
        ];
        if let Some(original) = original {
            environment.push(("LD_LIBRARY_PATH_ORIG", original));
        }
        let mut command = appimage_restart_command(
            std::path::Path::new("/usr/bin/env"),
            environment
                .into_iter()
                .map(|(key, value)| (key.into(), value.into())),
        );
        // Run only env, never an AppImage/installer. This checks the actual child
        // environment without mutating process-global variables in parallel tests.
        let output = command.output().unwrap();
        assert!(output.status.success());
        let output = String::from_utf8(output.stdout).unwrap();
        let environment: std::collections::BTreeMap<_, _> = output
            .lines()
            .map(|line| line.split_once('=').unwrap())
            .collect();
        assert_eq!(environment.get("APPIMAGE_EXTRACT_AND_RUN"), Some(&"1"));
        assert_eq!(environment.get("HOME"), Some(&"/user/home"));
        assert_eq!(environment.get("LD_LIBRARY_PATH").copied(), original);
        for stale in [
            "APPIMAGE",
            "APPDIR",
            "ARGV0",
            "OWD",
            "APPIMAGE_SILENT_INSTALL",
            "LD_LIBRARY_PATH_ORIG",
        ] {
            assert!(!environment.contains_key(stale), "Forwarded {stale}");
        }
        assert!(!output.contains("/tmp/.mount_old"));
    }
}
