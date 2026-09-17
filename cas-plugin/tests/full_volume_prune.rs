//! A prune has to run on a full volume, since that is when a runner's cache
//! image needs it. Needs `hdiutil` for a small APFS disk image, and skips
//! without it.

use std::path::{Path, PathBuf};
use std::process::Command;

use tuist_cas_plugin::proxy::{prune_store, StorePrune};

const MIB: usize = 1024 * 1024;

#[test]
fn a_prune_runs_on_a_full_volume_and_frees_it() {
    let Some(volume) = Volume::attach("tuist-cas-full-volume") else { return };
    let store = volume.mount.join("builtin");
    std::fs::create_dir_all(&store).unwrap();
    std::fs::write(store.join("lock"), b"").unwrap();
    write_generation(&store, 1, 8 * MIB);
    write_generation(&store, 2, 8 * MIB);
    let upstream = allocated(&store.join("v1.1"));
    fill(&volume.mount);
    assert!(std::fs::write(volume.mount.join("probe"), vec![0u8; MIB]).is_err());

    let pruned = prune_store(store.to_str().unwrap(), 4 * MIB as u64).unwrap();

    assert_eq!(pruned, StorePrune { reclaimed: upstream, held_open: false });
    assert_eq!(generations(&store), vec!["v1.2", "v1.3"]);
    std::fs::write(volume.mount.join("probe"), vec![0u8; MIB]).unwrap();
}

struct Volume {
    image: PathBuf,
    mount: PathBuf,
}

impl Volume {
    fn attach(label: &str) -> Option<Self> {
        let root = std::env::temp_dir().join(format!("{label}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let volume = Self { image: root.join("volume.dmg"), mount: root.join("mount") };
        let created = Command::new("hdiutil")
            .args(["create", "-quiet", "-size", "64m", "-fs", "APFS", "-type", "UDIF"])
            .arg(&volume.image)
            .status();
        let attached = created.is_ok_and(|status| status.success())
            && Command::new("hdiutil")
                .args(["attach", "-quiet", "-nobrowse", "-mountpoint"])
                .arg(&volume.mount)
                .arg(&volume.image)
                .status()
                .is_ok_and(|status| status.success());
        if !attached {
            eprintln!("skipping: could not create and attach an APFS disk image");
            let _ = std::fs::remove_dir_all(&root);
            return None;
        }
        Some(volume)
    }
}

impl Drop for Volume {
    fn drop(&mut self) {
        let _ = Command::new("hdiutil")
            .args(["detach", "-quiet", "-force"])
            .arg(&self.mount)
            .status();
        if let Some(root) = self.image.parent() {
            let _ = std::fs::remove_dir_all(root);
        }
    }
}

fn write_generation(store: &Path, index: u64, bytes: usize) {
    let generation = store.join(format!("v1.{index}"));
    std::fs::create_dir_all(&generation).unwrap();
    std::fs::write(generation.join("v9.data"), vec![0xA5u8; bytes]).unwrap();
}

fn fill(mount: &Path) {
    use std::io::Write;
    let mut filler = std::fs::File::create(mount.join("filler")).unwrap();
    for piece in [MIB, 64 * 1024, 4096] {
        while filler.write_all(&vec![0x5Au8; piece]).is_ok() {}
    }
    let _ = filler.sync_all();
}

fn allocated(path: &Path) -> u64 {
    use std::os::unix::fs::MetadataExt;
    std::fs::read_dir(path)
        .unwrap()
        .flatten()
        .map(|entry| entry.metadata().unwrap().blocks() * 512)
        .sum()
}

fn generations(store: &Path) -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(store)
        .unwrap()
        .flatten()
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .filter(|name| name.starts_with("v1."))
        .collect();
    names.sort();
    names
}
