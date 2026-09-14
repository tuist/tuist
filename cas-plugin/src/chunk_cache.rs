//! Disposable transfer bytes, separate from the compiler's object store.
//! A four-way cache bounds disk usage without scanning directories on a
//! compiler demand load. Collisions and interrupted writes are ordinary misses.
use crate::reapi::{blob_digest, Digest};
use std::{
    fs,
    io::{Read, Write},
    path::PathBuf,
};

pub struct ChunkCache {
    directory: PathBuf,
    scope: String,
}

impl ChunkCache {
    pub fn new(directory: PathBuf, scope: String) -> Self {
        Self { directory, scope }
    }

    #[cfg(test)]
    fn path(&self, digest: &Digest) -> PathBuf {
        self.paths(digest)[0].clone()
    }

    fn paths(&self, digest: &Digest) -> [PathBuf; 4] {
        let key = blob_digest(
            format!("{}\0{}\0{}", self.scope, digest.hash, digest.size_bytes).as_bytes(),
        );
        let bucket = u16::from_str_radix(&key.hash[..4], 16).unwrap() % 128;
        std::array::from_fn(|way| self.directory.join(format!("{bucket:02x}-{way}")))
    }

    pub fn get(&self, digest: &Digest) -> Option<Vec<u8>> {
        if !(1..=2 * 1024 * 1024).contains(&digest.size_bytes) {
            return None;
        }
        self.paths(digest).into_iter().find_map(|path| {
            let file = fs::File::open(path).ok()?;
            if file.metadata().ok()?.len() != digest.size_bytes as u64 {
                return None;
            }
            let mut bytes = Vec::new();
            file.take(digest.size_bytes as u64 + 1)
                .read_to_end(&mut bytes)
                .ok()?;
            (blob_digest(&bytes) == *digest).then_some(bytes)
        })
    }

    pub fn put(&self, digest: &Digest, bytes: &[u8]) {
        if !(1..=2 * 1024 * 1024).contains(&bytes.len()) || blob_digest(bytes) != *digest {
            return;
        }
        if fs::create_dir_all(&self.directory).is_err() {
            return;
        }
        let Ok(lock) = fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(false)
            .open(self.directory.join(".lock"))
        else {
            return;
        };
        if lock.lock().is_err() {
            return;
        }
        if self.get(digest).is_some() {
            return;
        }
        let destination = self
            .paths(digest)
            .into_iter()
            .min_by_key(|path| {
                path.metadata()
                    .and_then(|meta| meta.modified())
                    .unwrap_or(std::time::UNIX_EPOCH)
            })
            .unwrap();
        let temporary = self.directory.join(".pending");
        let result = (|| -> std::io::Result<()> {
            let mut file = fs::File::create(&temporary)?;
            file.write_all(bytes)?;
            fs::rename(&temporary, destination)
        })();
        if result.is_err() {
            let _ = fs::remove_file(temporary);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slot_selection_hashes_untrusted_digest_strings_before_indexing() {
        let cache = ChunkCache::new(PathBuf::from("unused"), "endpoint/project".into());
        for hash in ["", "x", "../../../outside", "not-hex", "💥"] {
            let paths = cache.paths(&Digest { hash: hash.into(), size_bytes: 1 });
            for (way, path) in paths.into_iter().enumerate() {
                assert_eq!(path.parent(), Some(std::path::Path::new("unused")));
                let name = path.file_name().unwrap().to_str().unwrap();
                let (bucket, slot) = name.split_once('-').unwrap();
                assert!(u8::from_str_radix(bucket, 16).unwrap() < 128);
                assert_eq!(slot, way.to_string());
            }
        }
    }

    #[test]
    fn persists_and_rejects_corrupt_or_oversized_slots() {
        let path = std::env::temp_dir().join(format!(
            "tuist-chunks-{}-{}",
            std::process::id(),
            crate::reapi::now_ms()
        ));
        let cache = ChunkCache::new(path.clone(), "endpoint/account/project".into());
        let digest = blob_digest(b"chunk bytes");
        cache.put(&digest, b"chunk bytes");
        let reopened = ChunkCache::new(path.clone(), "endpoint/account/project".into());
        assert_eq!(reopened.get(&digest).unwrap(), b"chunk bytes");
        fs::write(cache.path(&digest), b"wrong bytes").unwrap();
        assert!(cache.get(&digest).is_none());
        fs::write(cache.path(&digest), vec![0; 2 * 1024 * 1024 + 1]).unwrap();
        assert!(cache.get(&digest).is_none());
        fs::remove_dir_all(path).unwrap();
    }
}
