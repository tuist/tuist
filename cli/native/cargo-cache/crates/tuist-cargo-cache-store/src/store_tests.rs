use super::*;
use tuist_cargo_cache_core::{ActionPrediction, CacheFileNode, LocalActionCache};

fn store_object(store: &Path, contents: &[u8]) -> CacheDigest {
    let digest = CacheDigest::blake3(contents);
    LocalCas::new(store).store_bytes(&digest, contents).unwrap();
    digest
}

/// Backdate an object so eviction order is deterministic.
fn age(store: &Path, digest: &CacheDigest, age: Duration) {
    let path = LocalCas::new(store).path_for(digest).unwrap();
    let when = SystemTime::now() - age;
    let time = filetime::FileTime::from_system_time(when);
    filetime::set_file_times(path, time, time).unwrap();
}

/// Publish an action result whose output tree holds `outputs`.
fn store_result(store: &Path, name: &str, outputs: &[CacheDigest]) -> CacheDigest {
    let directory = CacheDirectory {
        directories: Vec::new(),
        files: outputs
            .iter()
            .enumerate()
            .map(|(index, digest)| CacheFileNode {
                digest: digest.clone(),
                executable: false,
                mode: 0o644,
                name: format!("output-{index}"),
            })
            .collect(),
        symlinks: Vec::new(),
        version: 1,
    };
    let encoded = serde_json::to_vec(&directory).unwrap();
    let output_root = store_object(store, &encoded);
    let action = store_object(store, name.as_bytes());
    LocalActionCache::new(store)
        .store(&RemoteActionResult {
            version: 1,
            action: action.clone(),
            metadata: None,
            output_root: Some(output_root),
        })
        .unwrap();
    action
}

fn prediction(label: impl AsRef<[u8]>) -> ActionPrediction {
    let invocation = CacheDigest::blake3(label.as_ref());
    ActionPrediction {
        action: CacheDigest::blake3(invocation.hash.as_bytes()),
        invocation,
        adapter: "rustc".into(),
        payload: "{}".into(),
    }
}

/// Record a checkout of `identity` and the manifest that roots `actions`.
///
/// The agent only accepts predictions over its socket, so the manifest is
/// written here instead. The predictions come from the public type rather
/// than hand-rolled JSON, leaving only the two wrapper fields to drift --
/// and `tuist_cargo_cache_core`'s own tests write a manifest through the agent and
/// read it back with the same accessor this uses, so drift shows up there.
fn record_build(store: &Path, identity: &str, workspace_root: &Path, actions: &[CacheDigest]) {
    record_build_in_group(store, identity, workspace_root, actions, None);
}

fn record_build_in_group(
    store: &Path,
    identity: &str,
    workspace_root: &Path,
    actions: &[CacheDigest],
    group: Option<&str>,
) {
    record_checkout(
        store,
        identity,
        workspace_root,
        &workspace_root.join("target"),
    )
    .unwrap();
    let predictions = actions
        .iter()
        .enumerate()
        .map(|(index, action)| ActionPrediction {
            invocation: CacheDigest::blake3(format!("{identity}-{index}").as_bytes()),
            action: action.clone(),
            adapter: "rustc".into(),
            payload: "{}".into(),
        })
        .collect::<Vec<_>>();
    let manifest = serde_json::json!({
        "version": 1,
        "task": identity,
        "predictions": &predictions,
    });
    let path = store
        .join("task-manifests")
        .join("v1")
        .join(format!("{identity}.json"));
    write_atomic(&path, &serde_json::to_vec(&manifest).unwrap()).unwrap();
    let run = CacheDigest::blake3(format!("run-{identity}-{group:?}-{actions:?}").as_bytes()).hash;
    record_build_receipt(store, &run, identity, workspace_root, group, predictions).unwrap();
}

#[test]
fn an_identical_receipt_is_left_standing() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    let identity = "a".repeat(64);
    let workspace = Path::new("/workspace/app");
    let predictions = vec![ActionPrediction {
        invocation: CacheDigest::blake3(b"invocation"),
        action: CacheDigest::blake3(b"action"),
        adapter: "rustc".into(),
        payload: "{}".into(),
    }];
    let run = |name: &str| CacheDigest::blake3(name.as_bytes()).hash;
    record_build_receipt(
        store,
        &run("first"),
        &identity,
        workspace,
        None,
        predictions.clone(),
    )
    .unwrap();
    let path = latest_receipt_path(store, workspace);
    let written = std::fs::metadata(&path).unwrap();

    // Same predictions: only the timestamp would differ, so nothing is written.
    record_build_receipt(
        store,
        &run("second"),
        &identity,
        workspace,
        None,
        predictions.clone(),
    )
    .unwrap();
    let kept = std::fs::metadata(&path).unwrap();
    assert_eq!(kept.modified().unwrap(), written.modified().unwrap());
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt as _;
        assert_eq!(kept.ino(), written.ino(), "the receipt was replaced");
    }

    // A different prediction set replaces it.
    let mut more = predictions;
    more.push(ActionPrediction {
        invocation: CacheDigest::blake3(b"other invocation"),
        action: CacheDigest::blake3(b"other action"),
        adapter: "rustc".into(),
        payload: "{}".into(),
    });
    record_build_receipt(
        store,
        &run("third"),
        &identity,
        workspace,
        None,
        more.clone(),
    )
    .unwrap();
    let receipt = read_build_receipt(&path).unwrap();
    assert_eq!(receipt.predictions, more);
}

#[test]
fn reports_an_empty_store() {
    let directory = tempfile::tempdir().unwrap();
    assert_eq!(stats(directory.path()).unwrap(), StoreStats::default());
}

#[test]
fn lists_largest_entries_in_descending_order() {
    let directory = tempfile::tempdir().unwrap();
    store_object(directory.path(), b"small");
    store_object(directory.path(), b"a much larger object");

    let entries = largest(directory.path(), 1).unwrap();

    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].kind, "object");
    assert_eq!(entries[0].bytes, 20);
}

#[test]
fn verification_reports_a_corrupt_object() {
    let directory = tempfile::tempdir().unwrap();
    let digest = store_object(directory.path(), b"original");
    let path = LocalCas::new(directory.path()).path_for(&digest).unwrap();
    std::fs::write(&path, b"corrupt!").unwrap();

    let outcome = verify(directory.path()).unwrap();

    assert_eq!(outcome.checked_objects, 1);
    assert_eq!(outcome.problems, vec![path]);
}

#[test]
fn verification_reports_a_result_whose_objects_are_gone() {
    let directory = tempfile::tempdir().unwrap();
    let output = store_object(directory.path(), b"output");
    let action = store_result(directory.path(), "compile", std::slice::from_ref(&output));
    let result_path = LocalActionCache::new(directory.path())
        .path_for(&action)
        .unwrap();
    let cas = LocalCas::new(directory.path());
    std::fs::remove_file(cas.path_for(&action).unwrap()).unwrap();

    let outcome = verify(directory.path()).unwrap();

    assert_eq!(outcome.checked_action_results, 1);
    assert!(
        outcome.problems.contains(&result_path),
        "a result pointing at a missing object is a problem: {:?}",
        outcome.problems
    );
}

#[test]
fn inspection_ignores_in_progress_staging_paths() {
    let directory = tempfile::tempdir().unwrap();
    let action = store_result(directory.path(), "compile", &[]);
    let cas_path = LocalCas::new(directory.path()).path_for(&action).unwrap();
    let result_path = LocalActionCache::new(directory.path())
        .path_for(&action)
        .unwrap();
    let staging_file = tempfile::NamedTempFile::new_in(cas_path.parent().unwrap()).unwrap();
    std::fs::write(staging_file.path(), vec![b'x'; 1_024]).unwrap();
    let staging_directory = tempfile::tempdir_in(result_path.parent().unwrap()).unwrap();
    std::fs::write(
        staging_directory.path().join("result.json"),
        vec![b'x'; 2_048],
    )
    .unwrap();

    let entries = largest(directory.path(), 10).unwrap();
    let outcome = verify(directory.path()).unwrap();

    assert_eq!(entries.len(), 3);
    assert!(
        entries
            .iter()
            .all(|entry| entry.path != staging_file.path())
    );
    assert!(
        entries
            .iter()
            .all(|entry| !entry.path.starts_with(staging_directory.path()))
    );
    assert_eq!(outcome.checked_objects, 2);
    assert_eq!(outcome.checked_action_results, 1);
    assert!(outcome.problems.is_empty());
}

#[test]
fn attributes_reachable_cache_bytes_to_a_workspace() {
    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path().join("workspace");
    std::fs::create_dir_all(&workspace).unwrap();
    let output = store_object(directory.path(), b"artifact");
    let action = store_result(directory.path(), "compile", &[output]);
    record_build(directory.path(), &"a".repeat(64), &workspace, &[action]);

    let projects = projects(directory.path()).unwrap();

    assert_eq!(projects.len(), 1);
    assert_eq!(projects[0].workspace_root, workspace);
    assert_eq!(projects[0].identities, 1);
    assert!(projects[0].action_bytes > 0);
    assert!(projects[0].live);
}

/// Publish an action whose output tree nests `deep` one directory down beside
/// `shared` at the top.
fn store_nested_result(store: &Path, shared: &CacheDigest, deep: &CacheDigest) -> CacheDigest {
    let file = |digest: &CacheDigest, name: &str| CacheFileNode {
        digest: digest.clone(),
        executable: false,
        mode: 0o644,
        name: name.into(),
    };
    let child = store_object(
        store,
        &serde_json::to_vec(&CacheDirectory {
            directories: Vec::new(),
            files: vec![file(deep, "deep")],
            symlinks: Vec::new(),
            version: 1,
        })
        .unwrap(),
    );
    let output_root = store_object(
        store,
        &serde_json::to_vec(&CacheDirectory {
            directories: vec![tuist_cargo_cache_core::CacheDirectoryNode {
                digest: child,
                mode: 0o755,
                name: "nested".into(),
            }],
            files: vec![file(shared, "shared")],
            symlinks: Vec::new(),
            version: 1,
        })
        .unwrap(),
    );
    let action = store_object(store, b"nested");
    LocalActionCache::new(store)
        .store(&RemoteActionResult {
            version: 1,
            action: action.clone(),
            metadata: None,
            output_root: Some(output_root),
        })
        .unwrap();
    action
}

#[test]
fn a_workspace_counts_each_reachable_object_once() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    let whole = store.join("whole");
    let partial = store.join("partial");
    std::fs::create_dir_all(&whole).unwrap();
    std::fs::create_dir_all(&partial).unwrap();
    let shared = store_object(store, &[1; 1_000]);
    let deep = store_object(store, &[2; 10_000]);
    let nested = store_nested_result(store, &shared, &deep);
    let flat = store_result(store, "flat", std::slice::from_ref(&shared));
    // Two identities in one workspace reach `shared` through both actions.
    record_build(store, &"a".repeat(64), &whole, &[nested]);
    record_build(store, &"b".repeat(64), &whole, std::slice::from_ref(&flat));
    record_build(
        store,
        &"c".repeat(64),
        &partial,
        std::slice::from_ref(&flat),
    );
    let cas = LocalCas::new(store);
    let size = |path: PathBuf| std::fs::metadata(path).unwrap().len();
    let flat_output_root = LocalActionCache::new(store)
        .find(&flat)
        .unwrap()
        .unwrap()
        .output_root
        .unwrap();
    let flat_bytes = size(LocalActionCache::new(store).path_for(&flat).unwrap())
        + [&flat, &flat_output_root, &shared]
            .into_iter()
            .map(|digest| size(cas.path_for(digest).unwrap()))
            .sum::<u64>();

    let projects = projects(store).unwrap();
    let bytes = |workspace: &Path| {
        projects
            .iter()
            .find(|project| project.workspace_root == workspace)
            .unwrap()
            .action_bytes
    };

    assert_eq!(bytes(&whole), stats(store).unwrap().total_bytes());
    assert_eq!(bytes(&partial), flat_bytes);
}

#[test]
fn live_cache_bytes_leave_out_workspaces_that_are_gone() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    let live = store.join("live");
    let gone = store.join("gone");
    std::fs::create_dir_all(&live).unwrap();
    std::fs::create_dir_all(&gone).unwrap();
    let output = store_object(store, b"artifact");
    let action = store_result(store, "compile", &[output]);
    record_build(store, &"a".repeat(64), &live, std::slice::from_ref(&action));
    record_build(store, &"b".repeat(64), &gone, &[action]);
    std::fs::remove_dir(&gone).unwrap();

    let live_bytes = projects(store)
        .unwrap()
        .into_iter()
        .find(|project| project.workspace_root == live)
        .unwrap()
        .action_bytes;

    assert_eq!(live_project_cache_bytes(store).unwrap(), vec![live_bytes]);
}

#[test]
fn project_usage_excludes_expired_claims() {
    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path().join("workspace");
    std::fs::create_dir_all(&workspace).unwrap();
    let action = store_result(directory.path(), "compile", &[]);
    let identity = "a".repeat(64);
    record_build(directory.path(), &identity, &workspace, &[action]);
    let stale = CheckoutRecord {
        version: CHECKOUT_RECORD_VERSION,
        workspace_root: workspace.clone(),
        target_dir: workspace.join("target"),
        updated_secs: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs()
            - CHECKOUT_RETENTION.as_secs()
            - 1,
    };
    write_atomic(
        &checkout_record_path(directory.path(), &identity, &workspace),
        &serde_json::to_vec(&stale).unwrap(),
    )
    .unwrap();

    let projects = projects(directory.path()).unwrap();

    assert_eq!(projects.len(), 1);
    assert_eq!(projects[0].workspace_root, workspace);
    assert_eq!(projects[0].identities, 0);
    assert_eq!(projects[0].action_bytes, 0);
    assert!(!projects[0].live);
}

#[cfg(unix)]
#[test]
fn project_usage_follows_a_recorded_target_symlink() {
    use std::os::unix::fs::symlink;

    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path().join("workspace");
    let actual_target = directory.path().join("managed-target");
    std::fs::create_dir_all(&workspace).unwrap();
    std::fs::create_dir_all(&actual_target).unwrap();
    std::fs::write(actual_target.join("artifact"), b"compiled").unwrap();
    symlink(&actual_target, workspace.join("target")).unwrap();
    record_build(directory.path(), &"a".repeat(64), &workspace, &[]);

    let projects = projects(directory.path()).unwrap();

    assert_eq!(projects[0].target_bytes, 8);
}

#[test]
fn a_checkout_with_no_target_directory_of_its_own_reports_none() {
    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path().join("workspace");
    std::fs::create_dir_all(workspace.join("src")).unwrap();
    std::fs::write(workspace.join("src/main.c"), vec![0_u8; 4096]).unwrap();
    record_checkout(directory.path(), &"a".repeat(64), &workspace, &workspace).unwrap();

    let projects = projects(directory.path()).unwrap();

    assert_eq!(
        projects[0].target_bytes, 0,
        "a source tree is not build output, however large it is"
    );
}

#[test]
fn target_sizes_are_cached_by_recorded_path() {
    let directory = tempfile::tempdir().unwrap();
    let target = directory.path().join("target");
    std::fs::create_dir_all(&target).unwrap();
    std::fs::write(target.join("artifact"), b"first").unwrap();
    let mut cache = BTreeMap::new();

    assert_eq!(cached_tree_bytes(&mut cache, &target), 5);
    std::fs::write(target.join("artifact"), b"changed after the walk").unwrap();
    assert_eq!(cached_tree_bytes(&mut cache, &target), 5);
}

#[test]
fn removes_only_the_requested_workspaces_checkout_claims() {
    let directory = tempfile::tempdir().unwrap();
    let first = directory.path().join("first");
    let second = directory.path().join("second");
    std::fs::create_dir_all(&first).unwrap();
    std::fs::create_dir_all(&second).unwrap();
    record_build(directory.path(), &"a".repeat(64), &first, &[]);
    record_build(directory.path(), &"b".repeat(64), &second, &[]);

    let outcome = remove_project(directory.path(), &first).unwrap();

    assert_eq!(outcome.removed_checkout_records, 1);
    let remaining = projects(directory.path()).unwrap();
    assert_eq!(remaining.len(), 1);
    assert_eq!(remaining[0].workspace_root, second);
}

#[test]
fn exports_and_imports_the_last_builds_complete_closure() {
    let source = tempfile::tempdir().unwrap();
    let destination = tempfile::tempdir().unwrap();
    let workspace = source.path().join("workspace");
    std::fs::create_dir_all(&workspace).unwrap();
    let output = store_object(source.path(), b"compiled artifact");
    let action = store_result(
        source.path(),
        "compile action",
        std::slice::from_ref(&output),
    );
    let identity = "a".repeat(64);
    record_build(
        source.path(),
        &identity,
        &workspace,
        std::slice::from_ref(&action),
    );
    let archive = source.path().join("build.tar");

    let exported = export_checkout(source.path(), &workspace, &archive).unwrap();
    let imported = import_archive(destination.path(), &archive).unwrap();

    assert_eq!(exported.actions, 1);
    assert_eq!(imported.actions, 1);
    assert_eq!(exported.objects, 3);
    assert_eq!(imported.objects, 3);
    assert!(
        LocalCas::new(destination.path())
            .find(&output)
            .unwrap()
            .is_some()
    );
    assert!(
        LocalActionCache::new(destination.path())
            .find(&action)
            .unwrap()
            .is_some()
    );
    assert_eq!(
        task_manifest_actions(destination.path(), &identity).unwrap(),
        vec![action]
    );
}

#[test]
fn exports_and_imports_named_attachment_objects() {
    let source = tempfile::tempdir().unwrap();
    let destination = tempfile::tempdir().unwrap();
    let workspace = source.path().join("workspace");
    std::fs::create_dir_all(&workspace).unwrap();
    let action = store_result(source.path(), "compile action", &[]);
    record_build(source.path(), &"7".repeat(64), &workspace, &[action]);
    let attachment = store_object(source.path(), b"Cargo scheduler state");
    let additions = ExportAdditions {
        attachments: BTreeMap::from([("cargo-state-v1".into(), attachment.clone())]),
        objects: BTreeSet::from([attachment.clone()]),
    };
    let archive = source.path().join("build.tar");

    let exported = export_checkout_with(source.path(), &workspace, &archive, additions).unwrap();
    let imported = import_archive_with_attachments(destination.path(), &archive).unwrap();

    assert_eq!(exported.actions, 1);
    assert_eq!(
        imported.attachments.get("cargo-state-v1"),
        Some(&attachment)
    );
    assert!(
        LocalCas::new(destination.path())
            .find(&attachment)
            .unwrap()
            .is_some()
    );
}

#[test]
fn reports_the_targets_represented_by_a_group() {
    let store = tempfile::tempdir().unwrap();
    let first = store.path().join("first");
    let second = store.path().join("second");
    std::fs::create_dir_all(&first).unwrap();
    std::fs::create_dir_all(&second).unwrap();
    let action = store_result(store.path(), "compile action", &[]);
    record_build_in_group(
        store.path(),
        &"6".repeat(64),
        &first,
        std::slice::from_ref(&action),
        Some("ci-job"),
    );
    record_build_in_group(
        store.path(),
        &"5".repeat(64),
        &second,
        &[action],
        Some("ci-job"),
    );

    assert_eq!(
        group_workspace_targets(store.path(), "ci-job").unwrap(),
        vec![
            WorkspaceTarget {
                workspace_root: first.clone(),
                target_dir: first.join("target"),
            },
            WorkspaceTarget {
                workspace_root: second.clone(),
                target_dir: second.join("target"),
            },
        ]
    );
}

#[cfg(target_os = "linux")]
#[test]
fn imports_sparse_files_emitted_by_the_exporter() {
    use std::io::{Seek, Write};

    let source = tempfile::tempdir().unwrap();
    let destination = tempfile::tempdir().unwrap();
    let workspace = source.path().join("workspace");
    std::fs::create_dir_all(&workspace).unwrap();
    let mut contents = vec![0; 8 * 1024 * 1024];
    *contents.last_mut().unwrap() = 1;
    let output = CacheDigest::blake3(&contents);
    let output_path = LocalCas::new(source.path()).path_for(&output).unwrap();
    std::fs::create_dir_all(output_path.parent().unwrap()).unwrap();
    let mut sparse = std::fs::File::create(&output_path).unwrap();
    sparse.set_len(contents.len() as u64).unwrap();
    sparse.seek(std::io::SeekFrom::End(-1)).unwrap();
    sparse.write_all(&[1]).unwrap();
    drop(sparse);
    let action = store_result(
        source.path(),
        "sparse output",
        std::slice::from_ref(&output),
    );
    record_build(
        source.path(),
        &"9".repeat(64),
        &workspace,
        std::slice::from_ref(&action),
    );
    let archive = source.path().join("sparse.tar");

    export_checkout(source.path(), &workspace, &archive).unwrap();
    let mut tar = tar::Archive::new(std::fs::File::open(&archive).unwrap());
    assert!(
        tar.entries()
            .unwrap()
            .any(|entry| entry.unwrap().header().entry_type().is_gnu_sparse()),
        "test fixture must exercise a GNU sparse tar entry"
    );
    import_archive(destination.path(), &archive).unwrap();

    assert_eq!(
        std::fs::read(LocalCas::new(destination.path()).path_for(&output).unwrap()).unwrap(),
        contents
    );
}

#[test]
fn export_refuses_an_incomplete_build_closure() {
    let source = tempfile::tempdir().unwrap();
    let workspace = source.path().join("workspace");
    std::fs::create_dir_all(&workspace).unwrap();
    let output = store_object(source.path(), b"compiled artifact");
    let action = store_result(
        source.path(),
        "compile action",
        std::slice::from_ref(&output),
    );
    record_build(source.path(), &"b".repeat(64), &workspace, &[action]);
    std::fs::remove_file(LocalCas::new(source.path()).path_for(&output).unwrap()).unwrap();
    let archive = source.path().join("incomplete.tar");

    let error = export_checkout(source.path(), &workspace, &archive).unwrap_err();

    assert!(
        error.to_string().contains("cache object is missing"),
        "{error:?}"
    );
    assert!(!archive.exists());
}

/// Replace the body of each named CAS object in `archive`, keeping its length
/// so that only the content digest is wrong.
fn corrupt_archive_objects(archive: &Path, targets: &[CacheDigest]) {
    use std::io::Read as _;

    let names = targets
        .iter()
        .map(|digest| {
            Path::new(CAS_DIR)
                .join(&digest.algorithm)
                .join(&digest.hash[..2])
                .join(format!("{}-{}", digest.hash, digest.size))
        })
        .collect::<BTreeSet<_>>();
    let mut members = Vec::new();
    {
        let mut source = tar::Archive::new(std::fs::File::open(archive).unwrap());
        for entry in source.entries().unwrap() {
            let mut entry = entry.unwrap();
            let path = entry.path().unwrap().into_owned();
            let mut body = Vec::new();
            entry.read_to_end(&mut body).unwrap();
            if names.contains(&path) {
                body = vec![b'x'; body.len()];
            }
            members.push((path, body));
        }
    }
    let mut builder = tar::Builder::new(std::fs::File::create(archive).unwrap());
    for (path, body) in members {
        let mut header = tar::Header::new_gnu();
        header.set_size(body.len() as u64);
        header.set_mode(0o644);
        builder
            .append_data(&mut header, &path, body.as_slice())
            .unwrap();
    }
    builder.finish().unwrap();
}

/// Export one action whose output tree holds `outputs`, and return the archive.
fn export_outputs(source: &Path, outputs: &[CacheDigest]) -> PathBuf {
    let workspace = source.join("workspace");
    std::fs::create_dir_all(&workspace).unwrap();
    let action = store_result(source, "compile action", outputs);
    record_build(
        source,
        &"c".repeat(64),
        &workspace,
        std::slice::from_ref(&action),
    );
    let archive = source.join("build.tar");
    export_checkout(source, &workspace, &archive).unwrap();
    archive
}

#[test]
fn exports_and_imports_a_directory_bundle() {
    let source = tempfile::tempdir().unwrap();
    let destination = tempfile::tempdir().unwrap();
    let workspace = source.path().join("workspace");
    std::fs::create_dir_all(&workspace).unwrap();
    let output = store_object(source.path(), b"compiled artifact");
    let action = store_result(
        source.path(),
        "compile action",
        std::slice::from_ref(&output),
    );
    let identity = "d".repeat(64);
    record_build(
        source.path(),
        &identity,
        &workspace,
        std::slice::from_ref(&action),
    );
    let bundle = source.path().join("bundle");

    let exported = export_checkout_as(
        source.path(),
        &workspace,
        &bundle,
        ExportAdditions::default(),
        ExportForm::Directory,
    )
    .unwrap();
    assert!(bundle.join(EXPORT_MANIFEST).is_file());
    let imported = import_archive(destination.path(), &bundle).unwrap();

    assert_eq!(exported.objects, 3);
    assert_eq!(imported.objects, 3);
    assert!(
        LocalCas::new(destination.path())
            .find(&output)
            .unwrap()
            .is_some()
    );
    assert_eq!(
        task_manifest_actions(destination.path(), &identity).unwrap(),
        vec![action]
    );
    // The bundle is consumed: its objects were moved, not copied.
    assert!(!bundle.exists(), "a directory bundle is removed on success");
}

#[test]
fn a_directory_export_replaces_whatever_the_destination_held() {
    let source = tempfile::tempdir().unwrap();
    let workspace = source.path().join("workspace");
    std::fs::create_dir_all(&workspace).unwrap();
    let output = store_object(source.path(), b"compiled artifact");
    let action = store_result(
        source.path(),
        "compile action",
        std::slice::from_ref(&output),
    );
    record_build(
        source.path(),
        &"e".repeat(64),
        &workspace,
        std::slice::from_ref(&action),
    );
    let bundle = source.path().join("bundle");
    std::fs::create_dir_all(bundle.join("stale")).unwrap();
    std::fs::write(bundle.join("stale").join("leftover"), b"old run").unwrap();

    export_checkout_as(
        source.path(),
        &workspace,
        &bundle,
        ExportAdditions::default(),
        ExportForm::Directory,
    )
    .unwrap();

    assert!(!bundle.join("stale").exists());
    assert!(bundle.join(EXPORT_MANIFEST).is_file());
}

#[cfg(unix)]
#[test]
fn import_refuses_a_directory_bundle_holding_a_symlink() {
    let source = tempfile::tempdir().unwrap();
    let destination = tempfile::tempdir().unwrap();
    let workspace = source.path().join("workspace");
    std::fs::create_dir_all(&workspace).unwrap();
    let output = store_object(source.path(), b"compiled artifact");
    let action = store_result(
        source.path(),
        "compile action",
        std::slice::from_ref(&output),
    );
    record_build(
        source.path(),
        &"f".repeat(64),
        &workspace,
        std::slice::from_ref(&action),
    );
    let bundle = source.path().join("bundle");
    export_checkout_as(
        source.path(),
        &workspace,
        &bundle,
        ExportAdditions::default(),
        ExportForm::Directory,
    )
    .unwrap();
    let secret = source.path().join("outside-the-bundle");
    std::fs::write(&secret, b"not part of any export").unwrap();
    std::os::unix::fs::symlink(&secret, bundle.join(CAS_DIR).join("blake3").join("link")).unwrap();

    let error = import_archive(destination.path(), &bundle).unwrap_err();

    assert!(error.to_string().contains("non-file entry"), "{error:?}");
    assert!(bundle.exists(), "a refused bundle is left alone");
}

#[cfg(unix)]
#[test]
fn import_refuses_a_directory_bundle_holding_a_hard_link() {
    let source = tempfile::tempdir().unwrap();
    let destination = tempfile::tempdir().unwrap();
    let workspace = source.path().join("workspace");
    std::fs::create_dir_all(&workspace).unwrap();
    let output = store_object(source.path(), b"compiled artifact");
    let action = store_result(
        source.path(),
        "compile action",
        std::slice::from_ref(&output),
    );
    record_build(
        source.path(),
        &"0".repeat(64),
        &workspace,
        std::slice::from_ref(&action),
    );
    let bundle = source.path().join("bundle");
    export_checkout_as(
        source.path(),
        &workspace,
        &bundle,
        ExportAdditions::default(),
        ExportForm::Directory,
    )
    .unwrap();
    let staged = bundle
        .join(CAS_DIR)
        .join(&output.algorithm)
        .join(&output.hash[..2])
        .join(format!("{}-{}", output.hash, output.size));
    let alias = source.path().join("alias");
    std::fs::hard_link(&staged, &alias).unwrap();

    let error = import_archive(destination.path(), &bundle).unwrap_err();

    assert!(error.to_string().contains("hard link"), "{error:?}");
}

#[test]
fn a_failed_directory_export_keeps_the_previous_bundle() {
    let source = tempfile::tempdir().unwrap();
    let workspace = source.path().join("workspace");
    std::fs::create_dir_all(&workspace).unwrap();
    let output = store_object(source.path(), b"compiled artifact");
    let action = store_result(
        source.path(),
        "compile action",
        std::slice::from_ref(&output),
    );
    record_build(
        source.path(),
        &"1".repeat(64),
        &workspace,
        std::slice::from_ref(&action),
    );
    let bundle = source.path().join("bundle");
    export_checkout_as(
        source.path(),
        &workspace,
        &bundle,
        ExportAdditions::default(),
        ExportForm::Directory,
    )
    .unwrap();
    // Break the closure so the next export fails before it publishes.
    std::fs::remove_file(LocalCas::new(source.path()).path_for(&output).unwrap()).unwrap();

    let error = export_checkout_as(
        source.path(),
        &workspace,
        &bundle,
        ExportAdditions::default(),
        ExportForm::Directory,
    )
    .unwrap_err();

    assert!(
        error.to_string().contains("cache object is missing"),
        "{error:?}"
    );
    assert!(
        bundle.join(EXPORT_MANIFEST).is_file(),
        "a failed export must leave the previous bundle in place"
    );
}

#[test]
fn import_rejects_an_object_whose_contents_were_tampered_with() {
    let source = tempfile::tempdir().unwrap();
    let destination = tempfile::tempdir().unwrap();
    let output = store_object(source.path(), b"compiled artifact");
    let archive = export_outputs(source.path(), std::slice::from_ref(&output));
    corrupt_archive_objects(&archive, std::slice::from_ref(&output));

    let error = import_archive(destination.path(), &archive).unwrap_err();

    assert!(
        error
            .to_string()
            .contains("cache export is incomplete or corrupt"),
        "{error:?}"
    );
    assert!(
        format!("{error:?}").contains("failed digest verification"),
        "{error:?}"
    );
    // Nothing may be published from a closure that failed to verify.
    assert_eq!(stats(destination.path()).unwrap(), StoreStats::default());
}

#[test]
fn import_rejects_an_object_whose_length_changed() {
    let source = tempfile::tempdir().unwrap();
    let destination = tempfile::tempdir().unwrap();
    let output = store_object(source.path(), b"compiled artifact");
    let archive = export_outputs(source.path(), std::slice::from_ref(&output));
    // Truncating changes the length, which the walk catches before hashing.
    let staged = Path::new(CAS_DIR)
        .join(&output.algorithm)
        .join(&output.hash[..2])
        .join(format!("{}-{}", output.hash, output.size));
    let mut members = Vec::new();
    {
        use std::io::Read as _;
        let mut reader = tar::Archive::new(std::fs::File::open(&archive).unwrap());
        for entry in reader.entries().unwrap() {
            let mut entry = entry.unwrap();
            let path = entry.path().unwrap().into_owned();
            let mut body = Vec::new();
            entry.read_to_end(&mut body).unwrap();
            if path == staged {
                body.truncate(1);
            }
            members.push((path, body));
        }
    }
    let mut builder = tar::Builder::new(std::fs::File::create(&archive).unwrap());
    for (path, body) in members {
        let mut header = tar::Header::new_gnu();
        header.set_size(body.len() as u64);
        header.set_mode(0o644);
        builder
            .append_data(&mut header, &path, body.as_slice())
            .unwrap();
    }
    builder.finish().unwrap();

    let error = import_archive(destination.path(), &archive).unwrap_err();

    assert!(
        format!("{error:?}").contains("failed digest verification"),
        "{error:?}"
    );
    assert_eq!(stats(destination.path()).unwrap(), StoreStats::default());
}

#[test]
fn import_names_the_same_corrupt_object_every_run() {
    let source = tempfile::tempdir().unwrap();
    let first = store_object(source.path(), b"first compiled artifact");
    let second = store_object(source.path(), b"second compiled artifact");
    let archive = export_outputs(source.path(), &[first.clone(), second.clone()]);
    corrupt_archive_objects(&archive, &[first.clone(), second.clone()]);
    // Staged objects share a prefix, so the lowest path is the lowest hash.
    let (lower, higher) = if first.hash < second.hash {
        (&first, &second)
    } else {
        (&second, &first)
    };

    let messages = (0..2)
        .map(|_| {
            let destination = tempfile::tempdir().unwrap();
            format!(
                "{:?}",
                import_archive(destination.path(), &archive).unwrap_err()
            )
        })
        .collect::<Vec<_>>();

    // Staging directories are named randomly, so the object named in the
    // message is the claim under test, not the message itself.
    for message in &messages {
        assert!(message.contains(&lower.hash), "{message:?}");
        assert!(!message.contains(&higher.hash), "{message:?}");
    }
}

#[test]
fn inspection_ignores_abandoned_import_staging() {
    let directory = tempfile::tempdir().unwrap();
    let live = store_object(directory.path(), b"live object");
    let abandoned = directory
        .path()
        .join(IMPORT_STAGING_DIR)
        .join("import-killed");
    let staged = abandoned.join(CAS_DIR).join("blake3").join("ab");
    std::fs::create_dir_all(&staged).unwrap();
    std::fs::write(
        staged.join(format!("{}-11", "a".repeat(64))),
        b"stale bytes",
    )
    .unwrap();

    let stats = stats(directory.path()).unwrap();
    let outcome = verify(directory.path()).unwrap();
    let entries = largest(directory.path(), 10).unwrap();

    assert_eq!(stats.objects, 1);
    assert_eq!(stats.object_bytes, live.size);
    assert_eq!(outcome.checked_objects, 1);
    assert!(outcome.problems.is_empty(), "{outcome:?}");
    assert_eq!(entries.len(), 1);
}

#[test]
fn gc_prunes_abandoned_import_staging() {
    let directory = tempfile::tempdir().unwrap();
    store_object(directory.path(), b"live object");
    let root = directory.path().join(IMPORT_STAGING_DIR);
    let killed = root.join("import-killed");
    let running = root.join("import-running");
    for staging in [&killed, &running] {
        std::fs::create_dir_all(staging.join(CAS_DIR)).unwrap();
        std::fs::write(staging.join(CAS_DIR).join("blob"), b"staged bytes").unwrap();
    }
    let stale = filetime::FileTime::from_system_time(
        SystemTime::now() - IMPORT_STAGING_RETENTION - Duration::from_secs(60),
    );
    filetime::set_file_times(&killed, stale, stale).unwrap();

    gc(directory.path(), u64::MAX).unwrap();

    assert!(!killed.exists(), "an abandoned staging tree must be swept");
    assert!(running.exists(), "a fresh staging tree must be left alone");
}

#[test]
fn export_refuses_a_corrupted_object_of_the_right_length() {
    let source = tempfile::tempdir().unwrap();
    let workspace = source.path().join("workspace");
    std::fs::create_dir_all(&workspace).unwrap();
    let output = store_object(source.path(), b"compiled artifact");
    let action = store_result(
        source.path(),
        "compile action",
        std::slice::from_ref(&output),
    );
    record_build(
        source.path(),
        &"2".repeat(64),
        &workspace,
        std::slice::from_ref(&action),
    );
    // Same length, different bytes: only a content hash catches this, so it is
    // exactly what a length check would wave through.
    let path = LocalCas::new(source.path()).path_for(&output).unwrap();
    std::fs::write(&path, vec![b'x'; output.size as usize]).unwrap();
    let archive = source.path().join("rotted.tar");

    let error = export_checkout(source.path(), &workspace, &archive).unwrap_err();

    assert!(
        format!("{error:?}").contains("failed digest verification"),
        "{error:?}"
    );
    assert!(!archive.exists(), "a corrupt closure must publish nothing");
}

#[test]
fn archive_paths_are_checked_by_component_not_by_spelling() {
    // A directory bundle is walked with the platform's separator, so on
    // Windows these carry backslashes where a tar entry would carry slashes.
    // Both have to pass, and this is the assertion that says so on that CI.
    validate_archive_path(&Path::new(CAS_DIR).join("blake3").join("ab").join("cd-1")).unwrap();
    validate_archive_path(
        &Path::new(ACTION_RESULTS_DIR)
            .join("blake3")
            .join("ab")
            .join("cd-1.json"),
    )
    .unwrap();
    validate_archive_path(Path::new(EXPORT_MANIFEST)).unwrap();

    let _ = validate_archive_path(&Path::new("elsewhere").join("file")).unwrap_err();
    let _ = validate_archive_path(&Path::new("cas").join("v2").join("blob")).unwrap_err();
    // The tree roots themselves are not members.
    let _ = validate_archive_path(Path::new(CAS_DIR)).unwrap_err();
}

#[test]
fn a_finished_import_leaves_no_staging_behind() {
    let source = tempfile::tempdir().unwrap();
    let destination = tempfile::tempdir().unwrap();
    let workspace = source.path().join("workspace");
    std::fs::create_dir_all(&workspace).unwrap();
    let output = store_object(source.path(), b"compiled artifact");
    let action = store_result(
        source.path(),
        "compile action",
        std::slice::from_ref(&output),
    );
    record_build(
        source.path(),
        &"3".repeat(64),
        &workspace,
        std::slice::from_ref(&action),
    );
    let archive = source.path().join("build.tar");
    export_checkout(source.path(), &workspace, &archive).unwrap();

    import_archive(destination.path(), &archive).unwrap();

    // The tree goes with its `TempDir`; the claim has to go with it, or every
    // import would leave one behind where no sweep walks.
    let staging = destination.path().join(IMPORT_STAGING_DIR);
    let leftovers = read_dir_or_empty(&staging).unwrap();
    assert!(
        leftovers.is_empty(),
        "import left {:?} behind",
        leftovers
            .iter()
            .map(|entry| entry.path())
            .collect::<Vec<_>>()
    );
}

#[test]
fn gc_reclaims_a_staging_claim_whose_tree_is_gone() {
    let directory = tempfile::tempdir().unwrap();
    store_object(directory.path(), b"live object");
    let root = directory.path().join(IMPORT_STAGING_DIR);
    std::fs::create_dir_all(&root).unwrap();
    let orphan = root.join("import-killed.lock");
    std::fs::write(&orphan, b"").unwrap();
    let stale = filetime::FileTime::from_system_time(
        SystemTime::now() - IMPORT_STAGING_RETENTION - Duration::from_secs(60),
    );
    filetime::set_file_times(&orphan, stale, stale).unwrap();

    gc(directory.path(), u64::MAX).unwrap();

    assert!(!orphan.exists(), "a claim with no tree must be reclaimed");
}

#[test]
fn gc_leaves_a_locked_import_staging_tree_alone() {
    let directory = tempfile::tempdir().unwrap();
    store_object(directory.path(), b"live object");
    let root = directory.path().join(IMPORT_STAGING_DIR);
    let held = root.join("import-running-long");
    std::fs::create_dir_all(held.join(CAS_DIR)).unwrap();
    std::fs::write(held.join(CAS_DIR).join("blob"), b"staged bytes").unwrap();
    // Old enough to sweep, but still claimed: a slow import on large storage
    // can outlive the retention window.
    let stale = filetime::FileTime::from_system_time(
        SystemTime::now() - IMPORT_STAGING_RETENTION - Duration::from_secs(60),
    );
    filetime::set_file_times(&held, stale, stale).unwrap();
    let _lock = lock_import_staging(&held).unwrap();

    gc(directory.path(), u64::MAX).unwrap();

    assert!(held.exists(), "a claimed staging tree must survive a sweep");
}

#[test]
fn export_requires_a_build_from_the_current_checkout() {
    let source = tempfile::tempdir().unwrap();
    let workspace = source.path().join("never-built");
    std::fs::create_dir_all(&workspace).unwrap();

    let error =
        export_checkout(source.path(), &workspace, &source.path().join("empty.tar")).unwrap_err();

    assert!(
        error
            .to_string()
            .contains("no completed tuist_cargo_cache build"),
        "{error:?}"
    );
}

#[test]
fn export_uses_only_the_checkouts_most_recent_build() {
    let source = tempfile::tempdir().unwrap();
    let destination = tempfile::tempdir().unwrap();
    let workspace = source.path().join("workspace");
    std::fs::create_dir_all(&workspace).unwrap();
    let old_action = store_result(source.path(), "old build", &[]);
    let old_identity = "c".repeat(64);
    record_build(
        source.path(),
        &old_identity,
        &workspace,
        std::slice::from_ref(&old_action),
    );
    let new_action = store_result(source.path(), "new build", &[]);
    let new_identity = "d".repeat(64);
    record_build(
        source.path(),
        &new_identity,
        &workspace,
        std::slice::from_ref(&new_action),
    );
    let archive = source.path().join("latest.tar");

    export_checkout(source.path(), &workspace, &archive).unwrap();
    import_archive(destination.path(), &archive).unwrap();

    let cache = LocalActionCache::new(destination.path());
    assert!(cache.find(&new_action).unwrap().is_some());
    assert!(cache.find(&old_action).unwrap().is_none());
    assert!(
        !task_manifest_path(destination.path(), &old_identity).exists(),
        "an older build's prediction manifest should not be bundled"
    );
}

#[test]
fn grouped_export_unions_parallel_build_receipts() {
    let source = tempfile::tempdir().unwrap();
    let destination = tempfile::tempdir().unwrap();
    let first_workspace = source.path().join("first-workspace");
    let second_workspace = source.path().join("second-workspace");
    std::fs::create_dir_all(&first_workspace).unwrap();
    std::fs::create_dir_all(&second_workspace).unwrap();
    let first_action = store_result(source.path(), "first grouped build", &[]);
    let second_action = store_result(source.path(), "second grouped build", &[]);
    let unrelated_action = store_result(source.path(), "unrelated build", &[]);
    record_build_in_group(
        source.path(),
        &"e".repeat(64),
        &first_workspace,
        std::slice::from_ref(&first_action),
        Some("github-run-42/test"),
    );
    record_build_in_group(
        source.path(),
        &"f".repeat(64),
        &second_workspace,
        std::slice::from_ref(&second_action),
        Some("github-run-42/test"),
    );
    record_build_in_group(
        source.path(),
        &"1".repeat(64),
        &first_workspace,
        std::slice::from_ref(&unrelated_action),
        Some("another-job"),
    );
    let archive = source.path().join("job.tar");

    let exported = export_group(source.path(), "github-run-42/test", &archive).unwrap();
    let imported = import_archive(destination.path(), &archive).unwrap();

    assert_eq!(exported.actions, 2);
    assert_eq!(imported.actions, 2);
    let cache = LocalActionCache::new(destination.path());
    assert!(cache.find(&first_action).unwrap().is_some());
    assert!(cache.find(&second_action).unwrap().is_some());
    assert!(cache.find(&unrelated_action).unwrap().is_none());
}

#[test]
fn grouped_export_keeps_each_commands_predictions_and_newest_conflicts() {
    let source = tempfile::tempdir().unwrap();
    let destination = tempfile::tempdir().unwrap();
    let identity = "e".repeat(64);
    let prediction = |invocation: &str, action: &str| ActionPrediction {
        invocation: CacheDigest::blake3(invocation.as_bytes()),
        action: store_result(source.path(), action, &[]),
        adapter: "rustc".into(),
        payload: "{}".into(),
    };
    let clippy = prediction("clippy", "clippy result");
    let test = prediction("test", "test result");
    let old_shared = prediction("shared", "old shared result");
    let new_shared = prediction("shared", "new shared result");
    let receipt = |completed_nanos, predictions| BuildReceipt {
        version: 1,
        workspace_root: source.path().join("workspace"),
        identity: identity.clone(),
        completed_nanos,
        group: Some("job".into()),
        predictions,
    };
    let archive = source.path().join("job.tar");
    // Deliberately supply reverse completion order.
    let exported = export_receipts(
        source.path(),
        vec![
            receipt(2, vec![test.clone(), new_shared.clone()]),
            receipt(1, vec![clippy.clone(), old_shared.clone()]),
        ],
        &archive,
        ExportAdditions::default(),
        ExportForm::Tar,
    )
    .unwrap();
    import_archive(destination.path(), &archive).unwrap();
    let manifest: TaskActionManifest = serde_json::from_slice(
        &std::fs::read(task_manifest_path(destination.path(), &identity)).unwrap(),
    )
    .unwrap();
    assert_eq!(
        manifest.predictions,
        vec![clippy.clone(), test.clone(), new_shared.clone()]
    );
    assert_eq!(manifest.predictions.len(), 3);
    for expected in [clippy, test, new_shared] {
        let actual = manifest
            .predictions
            .iter()
            .find(|p| p.invocation == expected.invocation)
            .unwrap();
        assert_eq!(actual.action, expected.action);
    }
    assert_eq!(exported.actions, 4);
    assert!(
        LocalActionCache::new(destination.path())
            .find(&old_shared.action)
            .unwrap()
            .is_some()
    );
}

#[test]
fn import_prunes_the_oldest_entry_from_a_full_manifest() {
    const TASK_MANIFEST_LIMIT: usize = 16 * 1024;

    let destination = tempfile::tempdir().unwrap();
    let identity = "3".repeat(64);
    let existing = (0..TASK_MANIFEST_LIMIT)
        .map(|index| prediction(index.to_le_bytes()))
        .collect::<Vec<_>>();
    let oldest = existing[0].clone();
    write_atomic(
        &task_manifest_path(destination.path(), &identity),
        &serde_json::to_vec(&TaskActionManifest {
            version: 1,
            task: identity.clone(),
            predictions: existing,
        })
        .unwrap(),
    )
    .unwrap();
    let imported = prediction(b"imported invocation");

    merge_imported_manifest(
        destination.path(),
        TaskActionManifest {
            version: 1,
            task: identity.clone(),
            predictions: vec![imported.clone()],
        },
    )
    .unwrap();

    let manifest: TaskActionManifest = serde_json::from_slice(
        &std::fs::read(task_manifest_path(destination.path(), &identity)).unwrap(),
    )
    .unwrap();
    assert_eq!(manifest.predictions.len(), TASK_MANIFEST_LIMIT);
    assert_eq!(manifest.predictions.last(), Some(&imported));
    assert!(!manifest.predictions.contains(&oldest));
}

#[test]
fn import_preserves_lru_order_and_existing_values() {
    let destination = tempfile::tempdir().unwrap();
    let identity = "4".repeat(64);
    let oldest = prediction(b"oldest");
    let untouched = prediction(b"untouched");
    let existing_overlap = prediction(b"overlap");
    let imported_oldest = prediction(b"imported oldest");
    let mut imported_overlap = existing_overlap.clone();
    imported_overlap.action = CacheDigest::blake3(b"bundle overlap action");
    let imported_newest = prediction(b"imported newest");
    write_atomic(
        &task_manifest_path(destination.path(), &identity),
        &serde_json::to_vec(&TaskActionManifest {
            version: 1,
            task: identity.clone(),
            predictions: vec![oldest.clone(), untouched.clone(), existing_overlap.clone()],
        })
        .unwrap(),
    )
    .unwrap();

    merge_imported_manifest(
        destination.path(),
        TaskActionManifest {
            version: 1,
            task: identity.clone(),
            predictions: vec![
                imported_oldest.clone(),
                imported_overlap,
                imported_newest.clone(),
            ],
        },
    )
    .unwrap();

    let manifest: TaskActionManifest = serde_json::from_slice(
        &std::fs::read(task_manifest_path(destination.path(), &identity)).unwrap(),
    )
    .unwrap();
    assert_eq!(
        manifest.predictions,
        vec![
            oldest,
            untouched,
            imported_oldest,
            existing_overlap,
            imported_newest,
        ]
    );
}

#[test]
fn import_waits_for_the_task_manifest_lock() {
    let destination = tempfile::tempdir().unwrap();
    let identity = "5".repeat(64);
    let lock_path = task_manifest_lock_path(destination.path(), &identity);
    std::fs::create_dir_all(lock_path.parent().unwrap()).unwrap();
    let mut held_lock = fslock::LockFile::open(&lock_path).unwrap();
    held_lock.lock().unwrap();
    let destination_path = destination.path().to_path_buf();
    let imported_identity = identity.clone();
    let (started_tx, started_rx) = std::sync::mpsc::channel();
    let (done_tx, done_rx) = std::sync::mpsc::channel();
    let importer = std::thread::spawn(move || {
        started_tx.send(()).unwrap();
        let result = merge_imported_manifest(
            &destination_path,
            TaskActionManifest {
                version: 1,
                task: imported_identity,
                predictions: vec![prediction(b"blocked import")],
            },
        );
        done_tx.send(result).unwrap();
    });
    started_rx.recv().unwrap();

    assert!(matches!(
        done_rx.recv_timeout(Duration::from_millis(100)),
        Err(std::sync::mpsc::RecvTimeoutError::Timeout)
    ));
    held_lock.unlock().unwrap();
    done_rx
        .recv_timeout(Duration::from_secs(5))
        .unwrap()
        .unwrap();
    importer.join().unwrap();
}

#[test]
fn equal_timestamp_exports_ignore_receipt_enumeration_order() {
    let source = tempfile::tempdir().unwrap();
    let identity = "e".repeat(64);
    let receipts = ["first", "second"].map(|name| BuildReceipt {
        version: 1,
        workspace_root: source.path().to_path_buf(),
        identity: identity.clone(),
        completed_nanos: 1,
        group: Some("job".into()),
        predictions: vec![ActionPrediction {
            invocation: CacheDigest::blake3(b"shared invocation"),
            action: store_result(source.path(), name, &[]),
            adapter: "rustc".into(),
            payload: "{}".into(),
        }],
    });
    let mut predictions = Vec::new();
    for order in [receipts.to_vec(), receipts.into_iter().rev().collect()] {
        let destination = tempfile::tempdir().unwrap();
        let archive = destination.path().join("job.tar");
        export_receipts(
            source.path(),
            order,
            &archive,
            ExportAdditions::default(),
            ExportForm::Tar,
        )
        .unwrap();
        import_archive(destination.path(), &archive).unwrap();
        let manifest: TaskActionManifest = serde_json::from_slice(
            &std::fs::read(task_manifest_path(destination.path(), &identity)).unwrap(),
        )
        .unwrap();
        assert_eq!(manifest.predictions.len(), 1);
        predictions.push(manifest.predictions);
    }
    assert_eq!(predictions[0], predictions[1]);
}

#[test]
fn collection_preserves_grouped_receipts_replaced_in_the_task_manifest() {
    let source = tempfile::tempdir().unwrap();
    let destination = tempfile::tempdir().unwrap();
    let workspace = source.path().join("workspace");
    std::fs::create_dir_all(&workspace).unwrap();
    let group = "github-run-42/repeated-task";
    let identity = "2".repeat(64);

    let first_output = store_object(source.path(), b"first compiled artifact");
    let first_action = store_result(
        source.path(),
        "first command action",
        std::slice::from_ref(&first_output),
    );
    record_build_in_group(
        source.path(),
        &identity,
        &workspace,
        std::slice::from_ref(&first_action),
        Some(group),
    );

    // A later Cargo command shares this task identity and replaces the current
    // manifest. Its earlier receipt still belongs to the grouped CI export.
    let second_output = store_object(source.path(), b"second compiled artifact");
    let second_action = store_result(
        source.path(),
        "second command action",
        std::slice::from_ref(&second_output),
    );
    record_build_in_group(
        source.path(),
        &identity,
        &workspace,
        std::slice::from_ref(&second_action),
        Some(group),
    );

    // Make the replaced action older than an unrelated object. Without the
    // receipt root, collection evicts its closure first and export fails with
    // "action result is missing".
    age(source.path(), &first_action, Duration::from_secs(60 * 60));
    age(source.path(), &first_output, Duration::from_secs(60 * 60));
    let spare = store_object(source.path(), b"unrelated spare");
    let before = stats(source.path()).unwrap().total_bytes();

    gc(source.path(), before - 1).unwrap();

    assert!(
        LocalActionCache::new(source.path())
            .find(&first_action)
            .unwrap()
            .is_some(),
        "a grouped receipt must keep a replaced action exportable"
    );
    assert!(
        LocalCas::new(source.path())
            .find(&first_output)
            .unwrap()
            .is_some()
    );
    assert!(
        LocalCas::new(source.path()).find(&spare).unwrap().is_none(),
        "collection should still reclaim objects no receipt needs"
    );

    let archive = source.path().join("job.tar");
    let exported = export_group(source.path(), group, &archive).unwrap();
    let imported = import_archive(destination.path(), &archive).unwrap();
    assert_eq!(exported.actions, 2);
    assert_eq!(imported.actions, 2);
    assert!(
        grouped_receipt_actions(source.path()).unwrap().is_empty(),
        "a successful export should retire the receipts it consumed"
    );

    let first_closure_bytes =
        rooted_action_objects(source.path(), std::iter::once(first_action.clone()))
            .into_iter()
            .map(|path| std::fs::metadata(path).unwrap().len())
            .sum::<u64>();
    gc(
        source.path(),
        stats(source.path())
            .unwrap()
            .total_bytes()
            .saturating_sub(first_closure_bytes),
    )
    .unwrap();
    assert!(
        LocalActionCache::new(source.path())
            .find(&first_action)
            .unwrap()
            .is_none(),
        "retired receipts must stop rooting replaced actions"
    );
}

#[test]
fn failed_group_export_keeps_its_receipts_pending() {
    let source = tempfile::tempdir().unwrap();
    let workspace = source.path().join("workspace");
    std::fs::create_dir_all(&workspace).unwrap();
    let group = "github-run-42/retry";
    let action = store_result(source.path(), "missing action", &[]);
    record_build_in_group(
        source.path(),
        &"3".repeat(64),
        &workspace,
        std::slice::from_ref(&action),
        Some(group),
    );
    let action_path = LocalActionCache::new(source.path())
        .path_for(&action)
        .unwrap();
    std::fs::remove_file(action_path).unwrap();

    let _ = export_group(source.path(), group, &source.path().join("job.tar")).unwrap_err();

    assert_eq!(
        grouped_receipt_actions(source.path()).unwrap(),
        BTreeSet::from([action]),
        "a failed export must leave its receipts available for retry"
    );
}

#[test]
fn counts_objects_and_results() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    store_object(store, b"first");
    store_object(store, b"second object");

    let stats = stats(store).unwrap();

    assert_eq!(stats.objects, 2);
    assert_eq!(stats.object_bytes, 5 + 13);
    assert_eq!(stats.total_bytes(), 18);
}

#[test]
fn keeps_the_store_under_its_budget_evicting_oldest_first() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    let old = store_object(store, b"0123456789");
    let recent = store_object(store, b"abcdefghij");
    age(store, &old, Duration::from_secs(60 * 60));
    age(store, &recent, Duration::from_secs(1));

    let outcome = gc(store, 10).unwrap();

    assert_eq!(outcome.removed_objects, 1);
    assert_eq!(outcome.removed_bytes, 10);
    assert_eq!(outcome.remaining_bytes, 10);
    let cas = LocalCas::new(store);
    assert!(cas.find(&old).unwrap().is_none());
    assert!(cas.find(&recent).unwrap().is_some());
}

#[test]
fn leaves_a_store_within_budget_alone() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    store_object(store, b"kept");

    let outcome = gc(store, 1024).unwrap();

    assert_eq!(
        outcome,
        GcOutcome {
            remaining_bytes: 4,
            ..GcOutcome::default()
        }
    );
    assert_eq!(stats(store).unwrap().objects, 1);
}

#[test]
fn dry_run_reports_evictions_without_removing_objects() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    let digest = store_object(store, b"kept for now");

    let outcome = gc_dry_run(store, 0).unwrap();

    assert_eq!(outcome.removed_objects, 1);
    assert!(LocalCas::new(store).find(&digest).unwrap().is_some());
}

#[test]
fn a_blocked_unrooted_object_does_not_cost_a_rooted_one() {
    let locked = PathBuf::from("locked-unrooted");
    let removable = PathBuf::from("removable-unrooted");
    let protected = PathBuf::from("rooted");
    let objects = [&locked, &removable, &protected]
        .into_iter()
        .map(|path| Entry {
            path: path.clone(),
            size: 10,
            used: SystemTime::UNIX_EPOCH,
        })
        .collect::<Vec<_>>();
    let rooted = HashSet::from([protected.clone()]);
    let mut attempted = Vec::new();

    let outcome = evict_objects(&objects, &rooted, 30, 5, |path| {
        attempted.push(path.to_path_buf());
        Ok(if path == locked {
            Removal::Blocked
        } else {
            Removal::Removed
        })
    })
    .unwrap();

    assert_eq!(attempted, vec![locked, removable]);
    assert_eq!(
        outcome,
        ObjectEvictions {
            removed_objects: 1,
            removed_bytes: 10,
            remaining_bytes: 20,
        },
        "a locked unrooted blob should leave the store over budget before protected objects are evicted"
    );
}

#[test]
fn drops_an_action_result_whose_descriptor_blob_is_gone() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    let action = store_object(store, b"action key");
    let output_root = store_object(store, b"output root blob");
    let result = RemoteActionResult {
        version: 1,
        action: action.clone(),
        metadata: None,
        output_root: Some(output_root.clone()),
    };
    let cache = LocalActionCache::new(store);
    cache.store(&result).unwrap();

    // Evict only the descriptor blob, leaving the output root in place.
    std::fs::remove_file(LocalCas::new(store).find(&action).unwrap().unwrap()).unwrap();

    let outcome = gc(store, u64::MAX).unwrap();

    // Left behind, this entry would report a hit that `store` could never
    // republish, since publication requires the descriptor blob.
    assert_eq!(outcome.removed_action_results, 1);
    assert!(cache.find(&action).unwrap().is_none());
}

#[test]
fn keeps_an_action_result_whose_blob_is_present_but_corrupt() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    let action = store_object(store, b"action key");
    LocalActionCache::new(store)
        .store(&RemoteActionResult {
            version: 1,
            action: action.clone(),
            metadata: None,
            output_root: None,
        })
        .unwrap();
    let path = LocalCas::new(store).path_for(&action).unwrap();
    std::fs::write(&path, b"corrupted!").unwrap();

    let outcome = gc(store, u64::MAX).unwrap();

    // The sweep does not read content, so this result survives and costs a
    // miss on restore. Verifying instead would re-hash the whole store.
    assert_eq!(outcome.removed_action_results, 0);
    assert!(path.exists());
}

#[test]
fn drops_action_results_left_without_their_objects() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    let action = store_object(store, b"action key");
    let metadata = store_object(store, b"metadata blob");
    let result = RemoteActionResult {
        version: 1,
        action: action.clone(),
        metadata: Some(metadata),
        output_root: None,
    };
    LocalActionCache::new(store).store(&result).unwrap();

    // A budget of zero evicts every object, orphaning the result.
    let outcome = gc(store, 0).unwrap();

    assert!(outcome.removed_objects >= 1);
    assert_eq!(outcome.removed_action_results, 1);
    assert!(
        LocalActionCache::new(store)
            .find(&action)
            .unwrap()
            .is_none()
    );
}

#[test]
fn evicts_objects_no_live_checkout_needs_before_older_rooted_ones() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("store");
    let live = directory.path().join("live");
    let deleted = directory.path().join("deleted");
    std::fs::create_dir_all(&live).unwrap();
    std::fs::create_dir_all(&deleted).unwrap();

    let kept = store_object(&store, b"0123456789");
    let dropped = store_object(&store, b"abcdefghij");
    record_build(
        &store,
        &"a".repeat(64),
        &live,
        &[store_result(
            &store,
            "live action",
            std::slice::from_ref(&kept),
        )],
    );
    record_build(
        &store,
        &"b".repeat(64),
        &deleted,
        &[store_result(
            &store,
            "deleted action",
            std::slice::from_ref(&dropped),
        )],
    );
    // The rooted object is the older one, so plain LRU would take it first.
    // The deleted checkout's action and tree objects are unrooted too, and
    // were written moments ago; `dropped` has to be older than those by more
    // than a slow runner takes to get here, or they go first and satisfy the
    // budget without it.
    age(&store, &kept, Duration::from_secs(2 * 60 * 60));
    age(&store, &dropped, Duration::from_secs(60 * 60));
    std::fs::remove_dir_all(&deleted).unwrap();

    gc(&store, stats(&store).unwrap().total_bytes() - 10).unwrap();

    let cas = LocalCas::new(&store);
    assert!(
        cas.find(&kept).unwrap().is_some(),
        "a live checkout still needs this object"
    );
    assert!(
        cas.find(&dropped).unwrap().is_none(),
        "nothing that still exists needs this object"
    );
}

#[test]
fn keeps_rooting_when_a_sibling_worktree_survives() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("store");
    let first = directory.path().join("first");
    let second = directory.path().join("second");
    std::fs::create_dir_all(&first).unwrap();
    std::fs::create_dir_all(&second).unwrap();

    // Worktrees of one dependency graph share an identity by design, so the
    // survivor's claim has to keep the whole identity rooted.
    let identity = "c".repeat(64);
    let shared = store_object(&store, b"shared artifact");
    let action = store_result(&store, "shared action", std::slice::from_ref(&shared));
    record_build(&store, &identity, &first, std::slice::from_ref(&action));
    record_build(&store, &identity, &second, &[action]);
    let spare = store_object(&store, b"unrooted spare");
    std::fs::remove_dir_all(&second).unwrap();

    let outcome = gc(&store, stats(&store).unwrap().total_bytes() - 1).unwrap();

    assert_eq!(outcome.removed_checkout_records, 1);
    let cas = LocalCas::new(&store);
    assert!(cas.find(&shared).unwrap().is_some());
    assert!(cas.find(&spare).unwrap().is_none());
}

#[test]
fn roots_objects_nested_in_an_output_tree() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("store");
    let checkout = directory.path().join("checkout");
    std::fs::create_dir_all(&checkout).unwrap();

    // The leaf artifact, not the descriptor, is where a build's bytes are.
    let artifact = store_object(&store, b"the compiled artifact");
    let action = store_result(&store, "an action", std::slice::from_ref(&artifact));
    record_build(&store, &"d".repeat(64), &checkout, &[action]);
    let spare = store_object(&store, b"unrooted spare");

    gc(&store, stats(&store).unwrap().total_bytes() - 1).unwrap();

    let cas = LocalCas::new(&store);
    assert!(cas.find(&artifact).unwrap().is_some());
    assert!(cas.find(&spare).unwrap().is_none());
}

#[test]
fn treats_a_store_with_no_checkout_records_as_plain_lru() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    // A store written before checkouts were recorded roots nothing, so it
    // has to keep collecting exactly as it did.
    let old = store_object(store, b"0123456789");
    let recent = store_object(store, b"abcdefghij");
    age(store, &old, Duration::from_secs(60 * 60));
    age(store, &recent, Duration::from_secs(1));

    gc(store, 10).unwrap();

    let cas = LocalCas::new(store);
    assert!(cas.find(&old).unwrap().is_none());
    assert!(cas.find(&recent).unwrap().is_some());
}

#[test]
fn drops_checkout_records_whose_worktree_is_gone() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("store");
    let discarded_parent = directory.path().join("temporary");
    let gone = discarded_parent.join("codex/worktree");
    std::fs::create_dir_all(&gone).unwrap();
    record_checkout(&store, &"e".repeat(64), &gone, &gone.join("target")).unwrap();

    assert_eq!(stats(&store).unwrap().live_checkouts, 1);
    // Codex and temporary-worktree managers discard the checkout together
    // with its parent hierarchy. The surviving temp directory is the nearest
    // ancestor that can corroborate the deletion.
    std::fs::remove_dir_all(&discarded_parent).unwrap();
    let after = stats(&store).unwrap();
    assert_eq!(after.stale_checkouts, 1);
    assert_eq!(after.live_checkouts, 0);

    let outcome = gc(&store, u64::MAX).unwrap();

    assert_eq!(outcome.removed_checkout_records, 1);
    assert_eq!(stats(&store).unwrap(), StoreStats::default());
}

#[test]
fn keeps_a_checkout_recorded_while_its_worktree_exists() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("store");
    let live = directory.path().join("live");
    std::fs::create_dir_all(&live).unwrap();
    record_checkout(&store, &"f".repeat(64), &live, &live.join("target")).unwrap();

    let outcome = gc(&store, u64::MAX).unwrap();

    assert_eq!(outcome.removed_checkout_records, 0);
    assert_eq!(stats(&store).unwrap().live_checkouts, 1);
}

#[test]
fn forgets_a_claim_no_build_has_renewed() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("store");
    let checkout = directory.path().join("checkout");
    std::fs::create_dir_all(&checkout).unwrap();

    // The checkout is still there, but this identity names a command line
    // against a lockfile that has since moved on, so nothing renews it.
    let identity = "2".repeat(64);
    let orphan = store_object(&store, b"what that command built");
    record_build(
        &store,
        &identity,
        &checkout,
        &[store_result(
            &store,
            "stale action",
            std::slice::from_ref(&orphan),
        )],
    );
    let stale = CheckoutRecord {
        version: CHECKOUT_RECORD_VERSION,
        workspace_root: checkout.clone(),
        target_dir: checkout.join("target"),
        updated_secs: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs()
            - CHECKOUT_RETENTION.as_secs()
            - 1,
    };
    write_atomic(
        &checkout_record_path(&store, &identity, &checkout),
        &serde_json::to_vec(&stale).unwrap(),
    )
    .unwrap();
    // The orphan must sort strictly oldest. One second was enough to beat
    // coarse filesystem timestamps, but it also raced the wall clock: the
    // descriptor and output tree above were written before `age` reads "now",
    // so a runner that stalls past the margin between those two moments makes
    // them the oldest objects instead, and collection under a barely-reduced
    // budget evicts one of them and leaves the orphan alone. An hour outruns
    // any plausible stall.
    age(&store, &orphan, Duration::from_secs(60 * 60));

    assert_eq!(stats(&store).unwrap().stale_checkouts, 1);
    gc(&store, stats(&store).unwrap().total_bytes() - 1).unwrap();

    assert!(
        LocalCas::new(&store).find(&orphan).unwrap().is_none(),
        "an expired claim roots nothing"
    );
}

#[test]
fn ignores_what_it_did_not_write_beside_the_checkout_records() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("store");
    let checkout = directory.path().join("project");
    std::fs::create_dir_all(&checkout).unwrap();
    record_checkout(&store, &"3".repeat(64), &checkout, &checkout.join("target")).unwrap();

    // A plain file whose name reads like an identity used to fail the scan,
    // and with it every sweep and every `cache stats`.
    let intruder = store.join(CHECKOUTS_DIR).join("4".repeat(64));
    std::fs::write(&intruder, b"not a directory of records").unwrap();
    std::fs::write(store.join(CHECKOUTS_DIR).join("notes.txt"), b"nor this").unwrap();

    assert_eq!(stats(&store).unwrap().live_checkouts, 1);
    assert_eq!(gc(&store, u64::MAX).unwrap().removed_checkout_records, 0);
    assert!(intruder.exists(), "and nothing of theirs is deleted either");
}

#[test]
fn corroborates_a_removed_checkout_through_its_nearest_existing_ancestor() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("store");
    std::fs::create_dir_all(&store).unwrap();

    // A checkout that is gone from a parent on the store's filesystem is worth
    // believing: that is what deleting a worktree looks like.
    let parent = directory.path().join("worktrees");
    std::fs::create_dir_all(&parent).unwrap();
    assert!(!checkout_is_live_on(&store, &parent.join("removed")));

    // Worktree managers remove their empty parent hierarchy too. The nearest
    // remaining ancestor still corroborates that this checkout was deleted.
    assert!(!checkout_is_live_on(
        &store,
        &directory.path().join("gone/deeper/still")
    ));

    // And anything still on disk is live whatever its parent says.
    assert!(checkout_is_live_on(&store, directory.path()));
}

#[cfg(target_os = "linux")]
#[test]
fn keeps_a_missing_checkout_beneath_a_different_filesystem() {
    let directory = tempfile::tempdir().unwrap();
    assert!(checkout_is_live_on(
        directory.path(),
        Path::new("/proc/tuist_cargo_cache-checkout-that-does-not-exist")
    ));
}

#[test]
fn sweeps_only_once_within_the_interval() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    store_object(store, b"kept");

    assert!(
        sweep_if_due(store, u64::MAX, Duration::from_secs(3600))
            .unwrap()
            .is_some()
    );
    assert!(
        sweep_if_due(store, u64::MAX, Duration::from_secs(3600))
            .unwrap()
            .is_none(),
        "the interval has not passed"
    );
    assert!(
        sweep_if_due(store, u64::MAX, Duration::ZERO)
            .unwrap()
            .is_some(),
        "a zero interval always sweeps"
    );
}

#[test]
fn concurrent_callers_claim_only_one_sweep() {
    let directory = tempfile::tempdir().unwrap();
    let store = std::sync::Arc::new(directory.path().to_path_buf());
    let barrier = std::sync::Arc::new(std::sync::Barrier::new(8));
    let callers = (0..8)
        .map(|_| {
            let store = store.clone();
            let barrier = barrier.clone();
            std::thread::spawn(move || {
                barrier.wait();
                claim_sweep(&store, Duration::from_secs(3600)).unwrap()
            })
        })
        .collect::<Vec<_>>();

    let claimed = callers
        .into_iter()
        .map(|caller| caller.join().unwrap())
        .filter(|claimed| *claimed)
        .count();

    assert_eq!(claimed, 1);
}

#[test]
fn claiming_existing_stamp_updates_its_mtime() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    let stamp = store.join(SWEEP_STAMP);
    std::fs::create_dir_all(stamp.parent().unwrap()).unwrap();
    let file = std::fs::File::create(&stamp).unwrap();
    file.set_modified(SystemTime::now() - Duration::from_secs(3600 * 2))
        .unwrap();
    let before = std::fs::metadata(&stamp).unwrap().modified().unwrap();

    assert!(claim_sweep(store, Duration::from_secs(3600)).unwrap());

    let after = std::fs::metadata(&stamp).unwrap().modified().unwrap();
    assert!(after > before, "claiming a due stamp refreshes its mtime");
    assert!(
        !claim_sweep(store, Duration::from_secs(3600)).unwrap(),
        "repeated claims inside the interval are throttled"
    );
}

#[test]
fn does_not_count_its_own_bookkeeping_against_the_budget() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("store");
    let checkout = directory.path().join("checkout");
    std::fs::create_dir_all(&checkout).unwrap();
    record_checkout(&store, &"1".repeat(64), &checkout, &checkout.join("target")).unwrap();
    sweep_if_due(&store, u64::MAX, Duration::ZERO).unwrap();

    // Checkout records and the sweep stamp live outside the collected
    // trees; counting them would make the budget mean something else.
    assert_eq!(stats(&store).unwrap().total_bytes(), 0);
}

/// Write a session event stream as though a build had left it behind.
fn write_session(store: &Path, id: &str, age: Duration) {
    let paths = crate::events::session_paths(store, id);
    std::fs::create_dir_all(paths.events.parent().unwrap()).unwrap();
    std::fs::write(
        &paths.events,
        "{\"type\":\"truncated\",\"v\":1,\"ts_ms\":1}\n",
    )
    .unwrap();
    let when = SystemTime::now() - age;
    let time = filetime::FileTime::from_system_time(when);
    filetime::set_file_times(&paths.events, time, time).unwrap();
}

fn session_count(store: &Path) -> usize {
    crate::events::session_ids(store).len()
}

#[test]
fn collection_drops_session_streams_past_their_retention() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("store");
    write_session(
        &store,
        "100-1-aaaa",
        SESSION_RETENTION + Duration::from_secs(60),
    );
    write_session(&store, "200-1-bbbb", Duration::from_secs(60));

    let outcome = gc(&store, u64::MAX).unwrap();

    assert_eq!(outcome.removed_session_streams, 1);
    assert!(outcome.removed_bytes > 0);
    // A stream's bytes are history, not cache content, so they are never part
    // of what the budget is measured against.
    assert_eq!(outcome.remaining_bytes, 0);
    assert_eq!(session_count(&store), 1);
}

#[test]
fn collection_keeps_only_the_newest_streams_however_new_they_are() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("store");
    // Ids sort oldest-first because they begin with a start time; pad so they
    // sort as numbers of the same width do.
    for index in 0..MAX_SESSIONS + 5 {
        write_session(
            &store,
            &format!("{index:06}-1-aaaa"),
            Duration::from_secs(1),
        );
    }

    let outcome = gc(&store, u64::MAX).unwrap();

    assert_eq!(outcome.removed_session_streams, 5);
    assert_eq!(session_count(&store), MAX_SESSIONS);
    // The five oldest went, not five arbitrary ones.
    let remaining = crate::events::session_ids(&store);
    assert_eq!(remaining.first().unwrap(), "000005-1-aaaa");
}

#[test]
fn collection_leaves_a_stream_a_build_is_still_writing() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("store");
    let writer = crate::events::EventWriter::new(&store);
    writer.started(Path::new("/workspace"), &["build".into()]);
    let live = writer.id().to_string();
    // Old enough to be swept, were anything but the lock protecting it.
    let paths = crate::events::session_paths(&store, &live);
    let when = SystemTime::now() - (SESSION_RETENTION + Duration::from_secs(60));
    let time = filetime::FileTime::from_system_time(when);
    filetime::set_file_times(&paths.events, time, time).unwrap();

    let outcome = gc(&store, u64::MAX).unwrap();

    assert_eq!(outcome.removed_session_streams, 0);
    assert!(paths.events.exists(), "a running build keeps its stream");

    // Once the build is gone, the same sweep collects it.
    drop(writer);
    let outcome = gc(&store, u64::MAX).unwrap();
    assert_eq!(outcome.removed_session_streams, 1);
    assert!(!paths.events.exists());
    assert!(
        !paths.lock.exists(),
        "the lock goes with the stream it named"
    );
}

#[test]
fn a_dry_run_reports_the_streams_it_would_drop_and_keeps_them() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("store");
    write_session(
        &store,
        "100-1-aaaa",
        SESSION_RETENTION + Duration::from_secs(60),
    );

    let outcome = gc_dry_run(&store, u64::MAX).unwrap();

    assert_eq!(outcome.removed_session_streams, 1);
    assert_eq!(session_count(&store), 1, "a dry run removes nothing");
}

#[test]
fn collection_removes_a_lock_whose_stream_never_appeared() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("store");
    // A lock is taken before the stream it names is created, so a failure in
    // between leaves one no listing of streams would reach.
    let paths = crate::events::session_paths(&store, "100-1-aaaa");
    std::fs::create_dir_all(paths.lock.parent().unwrap()).unwrap();
    std::fs::write(&paths.lock, b"").unwrap();

    gc(&store, u64::MAX).unwrap();

    assert!(!paths.lock.exists(), "an orphaned lock should be collected");
}

#[test]
fn collection_leaves_the_lock_of_a_stream_that_is_still_there() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("store");
    write_session(&store, "100-1-aaaa", Duration::from_secs(60));
    let paths = crate::events::session_paths(&store, "100-1-aaaa");
    std::fs::write(&paths.lock, b"").unwrap();

    gc(&store, u64::MAX).unwrap();

    // The stream is neither stale nor surplus, so neither it nor its lock is
    // any of collection's business.
    assert!(paths.events.exists());
    assert!(paths.lock.exists());
}

#[test]
fn a_due_sweep_is_reported_without_being_claimed() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    let interval = Duration::from_secs(3600);

    assert!(sweep_is_due(store, interval), "nothing has swept yet");
    assert!(
        sweep_is_due(store, interval),
        "asking did not stamp the store"
    );
    assert!(claim_sweep(store, interval).unwrap());
    assert!(
        !sweep_is_due(store, interval),
        "the claim is what stamps it"
    );
    assert!(sweep_is_due(store, Duration::ZERO));
}
