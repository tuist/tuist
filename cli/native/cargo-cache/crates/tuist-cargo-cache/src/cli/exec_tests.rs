use super::*;

#[test]
/// A non-colocated Jujutsu checkout is a project boundary.
fn discovers_a_jujutsu_project_root() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path();
    let nested = root.join("build").join("debug");
    std::fs::create_dir_all(&nested).unwrap();
    std::fs::create_dir(root.join(".jj")).unwrap();

    assert_eq!(discover_project_root(&nested), root);
}

#[test]
/// A nested Git checkout takes precedence over an enclosing Jujutsu checkout.
fn discovers_a_nested_git_project_root() {
    let directory = tempfile::tempdir().unwrap();
    let outer = directory.path();
    let inner = outer.join("vendor");
    let nested = inner.join("src");
    std::fs::create_dir_all(&nested).unwrap();
    std::fs::create_dir(outer.join(".jj")).unwrap();
    std::fs::create_dir(inner.join(".git")).unwrap();

    assert_eq!(discover_project_root(&nested), inner);
}

#[test]
/// A Delta-managed checkout is a project boundary despite having no VCS marker.
fn discovers_a_delta_worktree_project_root() {
    let directory = tempfile::tempdir().unwrap();
    let repository = directory.path().join("project");
    let worktree = repository.join(".delta/worktrees/thread");
    let nested = worktree.join("src/build");
    std::fs::create_dir_all(&nested).unwrap();
    std::fs::create_dir(repository.join(".git")).unwrap();

    assert_eq!(discover_project_root(&nested), worktree);
}

#[test]
/// Native Mercurial and Sapling markers establish project boundaries.
fn discovers_mercurial_and_sapling_project_roots() {
    for marker in [".hg", ".sl"] {
        let directory = tempfile::tempdir().unwrap();
        let outer = directory.path();
        let checkout = outer.join(marker.trim_start_matches('.'));
        let nested = checkout.join("src/build");
        std::fs::create_dir_all(&nested).unwrap();
        std::fs::create_dir(outer.join(".git")).unwrap();
        std::fs::create_dir(checkout.join(marker)).unwrap();

        assert_eq!(discover_project_root(&nested), checkout, "marker: {marker}");
    }
}
