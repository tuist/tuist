//! Streaming builder for action `input_digest` values.
//!
//! Plugins all need the same shape: a domain-separation prefix, a
//! deterministic concatenation of `(label, content_digest)` pairs, and
//! a small set of plugin-specific tail values (toolchain identity,
//! Apple SDK env, dep action digests). Open-coding it in every plugin
//! invites subtle drift: a missed sort, a forgotten NUL terminator, a
//! domain prefix that collides across two plugins. This builder is the
//! one canonical implementation.

use std::path::Path;

use once_cas::Digest;

#[derive(Debug)]
/// Build an input digest piece by piece.
///
/// The encoding is `domain || (label || 0 || digest_bytes || 0)*` plus
/// any caller-appended tail bytes. NUL terminators delimit fields so
/// that two distinct `(label, digest)` sequences can never collide
/// after concatenation. Sources should be added in sorted order; the
/// builder does not sort on the caller's behalf because some plugins
/// (the Rust compiler, for example) need to mix sources, dep digests,
/// and tail keys in a specific order that's part of their cache-key
/// contract.
#[must_use]
pub struct InputDigestBuilder {
    buf: Vec<u8>,
}

impl InputDigestBuilder {
    /// Begin a new digest with `domain` as the leading prefix. Bumping
    /// the domain (e.g. from `once.rust.input.v1` to `...v2`) is the
    /// portable way to invalidate an entire plugin's cache namespace
    /// when its encoding changes.
    pub fn new(domain: &[u8]) -> Self {
        let mut buf = Vec::with_capacity(domain.len() + 64);
        buf.extend_from_slice(domain);
        Self { buf }
    }

    /// Append a `(label, digest)` pair. Most plugins use this for
    /// source files (label = workspace path) and for dep records
    /// (label = `dep:<label>` or similar prefix).
    pub fn push_keyed(&mut self, label: &[u8], digest: &Digest) -> &mut Self {
        self.buf.extend_from_slice(label);
        self.buf.push(0);
        self.buf.extend_from_slice(digest.as_bytes());
        self.buf.push(0);
        self
    }

    /// Append arbitrary bytes (e.g. a toolchain identifier).
    pub fn push_bytes(&mut self, bytes: &[u8]) -> &mut Self {
        self.buf.extend_from_slice(bytes);
        self.buf.push(0);
        self
    }

    /// Hash a workspace-relative source file and append the result
    /// keyed by the workspace-relative path. Streams the file through
    /// [`Digest::of_reader`] so multi-megabyte sources never sit in
    /// memory.
    pub fn push_source<P: AsRef<Path>>(
        &mut self,
        workspace_root: P,
        ws_rel: &str,
    ) -> std::io::Result<&mut Self> {
        let abs = workspace_root.as_ref().join(ws_rel);
        let file = std::fs::File::open(&abs)?;
        let digest = Digest::of_reader(std::io::BufReader::new(file))?;
        Ok(self.push_keyed(ws_rel.as_bytes(), &digest))
    }

    /// Finalise the buffer into a [`Digest`].
    pub fn finish(self) -> Digest {
        Digest::of_bytes(&self.buf)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn empty_digest_only_hashes_the_domain() {
        let a = InputDigestBuilder::new(b"d").finish();
        let b = InputDigestBuilder::new(b"d").finish();
        assert_eq!(a, b, "deterministic for the same domain");
        let c = InputDigestBuilder::new(b"d2").finish();
        assert_ne!(a, c, "domain bump partitions cache slots");
    }

    #[test]
    fn pushed_pairs_change_the_digest() {
        let one = {
            let mut b = InputDigestBuilder::new(b"d");
            b.push_keyed(b"path", &Digest::of_bytes(b"X"));
            b.finish()
        };
        let two = {
            let mut b = InputDigestBuilder::new(b"d");
            b.push_keyed(b"path", &Digest::of_bytes(b"Y"));
            b.finish()
        };
        assert_ne!(one, two);
    }

    #[test]
    fn push_source_hashes_file_contents() {
        let tmp = TempDir::new().unwrap();
        std::fs::create_dir_all(tmp.path().join("pkg")).unwrap();
        std::fs::write(tmp.path().join("pkg/main.rs"), b"fn main() {}").unwrap();

        let first = {
            let mut b = InputDigestBuilder::new(b"test.input.v1");
            b.push_source(tmp.path(), "pkg/main.rs").unwrap();
            b.finish()
        };
        let second = {
            let mut b = InputDigestBuilder::new(b"test.input.v1");
            b.push_source(tmp.path(), "pkg/main.rs").unwrap();
            b.finish()
        };
        assert_eq!(first, second, "stable for identical content");

        std::fs::write(tmp.path().join("pkg/main.rs"), b"fn main() { /*!*/ }").unwrap();
        let third = {
            let mut b = InputDigestBuilder::new(b"test.input.v1");
            b.push_source(tmp.path(), "pkg/main.rs").unwrap();
            b.finish()
        };
        assert_ne!(first, third, "content change invalidates the digest");
    }

    #[test]
    fn push_source_propagates_io_errors() {
        let tmp = TempDir::new().unwrap();
        let mut b = InputDigestBuilder::new(b"d");
        let err = b.push_source(tmp.path(), "missing.rs").unwrap_err();
        assert_eq!(err.kind(), std::io::ErrorKind::NotFound);
    }
}
