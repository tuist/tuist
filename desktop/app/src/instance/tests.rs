use super::*;

#[test]
fn forwards_warm_launches_and_reclaims_stale_endpoints() {
    let directory = std::env::temp_dir().join(format!("tuist-instance-{}", std::process::id()));
    std::fs::create_dir_all(&directory).unwrap();
    let first = Instance::start(&directory, vec!["tuist://app/profile".into()])
        .unwrap()
        .unwrap();
    assert_eq!(
        first.links.recv_blocking().unwrap(),
        ["tuist://app/profile"]
    );
    assert!(
        Instance::start(&directory, vec!["tuist://app/previews".into()])
            .unwrap()
            .is_none()
    );
    assert_eq!(
        first.links.recv_blocking().unwrap(),
        ["tuist://app/previews"]
    );
    assert!(Instance::start(&directory, vec![]).unwrap().is_none());
    assert!(first.links.recv_blocking().unwrap().is_empty());

    let mut forged = read_endpoint(&directory.join("desktop-instance.json")).unwrap();
    forged.token = "wrong-token".into();
    assert!(forward(forged, &["tuist://app/profile".into()]).is_err());
    assert!(first.links.try_recv().is_err());
    let endpoint = read_endpoint(&directory.join("desktop-instance.json")).unwrap();
    assert!(forward(endpoint, &vec!["tuist://app/profile".into(); 17]).is_err());
    assert!(first.links.try_recv().is_err());

    drop(first);
    let replacement = Instance::start(&directory, vec!["tuist://app/previews".into()])
        .unwrap()
        .unwrap();
    assert_eq!(
        replacement.links.recv_blocking().unwrap(),
        ["tuist://app/previews"]
    );
    drop(replacement);
    std::fs::remove_dir_all(directory).unwrap();
}
