//! Immutable Parquet input owned by a process-independent Erlang environment.
//! Large off-heap binaries are referenced, not copied. Bytes clones share the
//! owner, so Arrow readers may outlive the calling process without dangling.
use bytes::Bytes;
use rustler::env::SavedTerm;
use rustler::{Binary, OwnedEnv};

struct Owner {
    _saved: SavedTerm,
    _env: OwnedEnv,
    ptr: *const u8,
    len: usize,
}
// The immutable binary is kept alive by OwnedEnv, which can be freed on any
// thread. Nothing allocates in this environment after obtaining the pointer.
unsafe impl Send for Owner {}
impl AsRef<[u8]> for Owner {
    fn as_ref(&self) -> &[u8] {
        // SAFETY: the saved binary's immutable storage outlives this owner.
        unsafe { std::slice::from_raw_parts(self.ptr, self.len) }
    }
}
pub fn from_binary(binary: Binary<'_>) -> Bytes {
    let env = OwnedEnv::new();
    let saved = env.save(binary);
    let (ptr, len) = env.run(|e| {
        let b: Binary = saved.load(e).decode().expect("saved binary");
        (b.as_slice().as_ptr(), b.len())
    });
    Bytes::from_owner(Owner {
        _saved: saved,
        _env: env,
        ptr,
        len,
    })
}
