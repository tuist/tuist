//! Inspect the output graphs named by Xcode's compilation-cache remarks.
//!
//! Run against an idle disposable compiler store, not a developer's live store:
//! opening and reading Apple's store can fault nodes into its active generation.
//! No network requests, action writes, or format transformations are performed.
//! Usage: cargo run --release --example cache_output_inventory -- STORE BUILD_LOG

use serde::Serialize;
use std::{
    collections::{BTreeMap, BTreeSet},
    ffi::{c_char, CStr, CString},
    fs,
    path::Path,
    ptr,
};
use tuist_cas_plugin::{
    reapi::{blob_digest, compress_frame, compress_frame_for_transfer, encode_frame},
    types::*,
    upstream::Upstream,
    upstream_path,
};

const TRANSFER_THRESHOLD: usize = 2 * 1024 * 1024;
const MAX_NODE_BYTES: usize = 256 * 1024 * 1024;
const MAX_GRAPH_BYTES: usize = 1024 * 1024 * 1024;
const MAX_NODES: usize = 100_000;

#[derive(Serialize)]
struct Node {
    bytes: usize,
    references: usize,
    prefix_hex: String,
    whole_frame_bytes: usize,
    negotiated_frame_bytes: usize,
    chunk_eligible: bool,
    transfer_chunks: Vec<(String, usize)>,
}

#[derive(Serialize)]
struct Output {
    kind: String,
    root: String,
    nodes: BTreeMap<String, Node>,
}

fn output_references(log: &str) -> BTreeSet<(String, String)> {
    log.lines()
        .filter_map(|line| {
            let marker = "using cas output ";
            let start = line.to_ascii_lowercase().find(marker)? + marker.len();
            let (kind, tail) = line[start..].split_once(": ")?;
            let digest = tail.split_whitespace().next()?;
            digest
                .starts_with("0~")
                .then(|| (kind.into(), digest.into()))
        })
        .collect()
}

struct Store<'a> {
    up: &'a Upstream,
    cas: llcas_cas_t,
}

impl<'a> Store<'a> {
    fn open(up: &'a Upstream, path: &Path) -> Result<Self, String> {
        if !path.is_dir() {
            return Err("compiler store must already exist".into());
        }
        let path = CString::new(path.to_string_lossy().as_bytes()).map_err(|e| e.to_string())?;
        unsafe {
            let options = (up.llcas_cas_options_create)();
            (up.llcas_cas_options_set_client_version)(
                options,
                LLCAS_VERSION_MAJOR,
                LLCAS_VERSION_MINOR,
            );
            (up.llcas_cas_options_set_ondisk_path)(options, path.as_ptr());
            let mut error = ptr::null_mut();
            let cas = (up.llcas_cas_create)(options, &mut error);
            (up.llcas_cas_options_dispose)(options);
            let message = take_error(up, error);
            if cas.is_null() {
                return Err(format!("opening compiler store: {message}"));
            }
            Ok(Self { up, cas })
        }
    }

    fn read(&self, digest: &[u8]) -> Result<(Vec<Vec<u8>>, Vec<u8>), String> {
        unsafe {
            let mut id = llcas_objectid_t { opaque: 0 };
            let mut error = ptr::null_mut();
            let failed = (self.up.llcas_cas_get_objectid)(
                self.cas,
                llcas_digest_t {
                    data: digest.as_ptr(),
                    size: digest.len(),
                },
                &mut id,
                &mut error,
            );
            let message = take_error(self.up, error);
            if failed {
                return Err(format!("decoding object identifier: {message}"));
            }
            error = ptr::null_mut();
            let mut loaded = llcas_loaded_object_t { opaque: 0 };
            let result = (self.up.llcas_cas_load_object)(self.cas, id, &mut loaded, &mut error);
            let message = take_error(self.up, error);
            if result != LLCAS_LOOKUP_RESULT_SUCCESS {
                return Err(format!("output graph is incomplete: {message}"));
            }
            let data = (self.up.llcas_loaded_object_get_data)(self.cas, loaded);
            let refs = (self.up.llcas_loaded_object_get_refs)(self.cas, loaded);
            let count = (self.up.llcas_object_refs_get_count)(self.cas, refs);
            if data.size > MAX_NODE_BYTES || count > MAX_NODES {
                return Err("node exceeds diagnostic limits".into());
            }
            let refs = (0..count)
                .map(|index| {
                    let id = (self.up.llcas_object_refs_get_id)(self.cas, refs, index);
                    let digest = (self.up.llcas_objectid_get_digest)(self.cas, id);
                    std::slice::from_raw_parts(digest.data, digest.size).to_vec()
                })
                .collect();
            let bytes = if data.size == 0 {
                Vec::new()
            } else {
                std::slice::from_raw_parts(data.data.cast::<u8>(), data.size).to_vec()
            };
            Ok((refs, bytes))
        }
    }

    fn inventory(&self, kind: String, root: String) -> Result<Output, String> {
        let digest = self.parse_digest(&root)?;
        let mut pending = vec![digest];
        let mut nodes = BTreeMap::new();
        let mut total_bytes = 0;
        while let Some(digest) = pending.pop() {
            let key = self.print_digest(&digest)?;
            if nodes.contains_key(&key) {
                continue;
            }
            if nodes.len() >= MAX_NODES || pending.len() > MAX_NODES {
                return Err("output graph exceeds diagnostic node limit".into());
            }
            let (refs, bytes) = self
                .read(&digest)
                .map_err(|e| format!("{kind} {key}: {e}"))?;
            total_bytes += bytes.len();
            if total_bytes > MAX_GRAPH_BYTES {
                return Err("output graph exceeds diagnostic byte limit".into());
            }
            let frame = encode_frame(&refs, &bytes);
            let whole_frame_bytes = compress_frame(&frame).len();
            let (negotiated, _) = compress_frame_for_transfer(&frame, true);
            let chunk_eligible = negotiated.len() >= TRANSFER_THRESHOLD;
            let transfer_chunks = if chunk_eligible {
                fastcdc::v2020::FastCDC::with_level(
                    &negotiated,
                    128 * 1024,
                    512 * 1024,
                    2 * 1024 * 1024,
                    fastcdc::v2020::Normalization::Level2,
                )
                .map(|chunk| {
                    (
                        blob_digest(&negotiated[chunk.offset..chunk.offset + chunk.length]).hash,
                        chunk.length,
                    )
                })
                .collect()
            } else {
                vec![]
            };
            nodes.insert(
                key,
                Node {
                    bytes: bytes.len(),
                    references: refs.len(),
                    prefix_hex: bytes.iter().take(16).map(|b| format!("{b:02x}")).collect(),
                    whole_frame_bytes,
                    negotiated_frame_bytes: negotiated.len(),
                    chunk_eligible,
                    transfer_chunks,
                },
            );
            pending.extend(refs);
        }
        Ok(Output { kind, root, nodes })
    }

    fn parse_digest(&self, printed: &str) -> Result<Vec<u8>, String> {
        let printed = CString::new(printed).map_err(|e| e.to_string())?;
        let mut bytes = vec![0; 256];
        unsafe {
            let mut error = ptr::null_mut();
            let size = (self.up.llcas_digest_parse)(
                self.cas,
                printed.as_ptr(),
                bytes.as_mut_ptr(),
                bytes.len(),
                &mut error,
            );
            let message = take_error(self.up, error);
            if size == 0 || size as usize > bytes.len() || !message.is_empty() {
                return Err(format!("invalid object digest: {message}"));
            }
            bytes.truncate(size as usize);
        }
        Ok(bytes)
    }

    fn print_digest(&self, digest: &[u8]) -> Result<String, String> {
        unsafe {
            let mut printed = ptr::null_mut();
            let mut error = ptr::null_mut();
            let failed = (self.up.llcas_digest_print)(
                self.cas,
                llcas_digest_t {
                    data: digest.as_ptr(),
                    size: digest.len(),
                },
                &mut printed,
                &mut error,
            );
            let message = take_error(self.up, error);
            let result = take_error(self.up, printed);
            if failed {
                return Err(format!("printing object digest: {message}"));
            }
            Ok(result)
        }
    }
}

impl Drop for Store<'_> {
    fn drop(&mut self) {
        unsafe { (self.up.llcas_cas_dispose)(self.cas) };
    }
}

unsafe fn take_error(up: &Upstream, error: *mut c_char) -> String {
    if error.is_null() {
        return String::new();
    }
    let message = CStr::from_ptr(error).to_string_lossy().into_owned();
    (up.llcas_string_dispose)(error);
    message
}

fn main() -> Result<(), String> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args.len() != 2 {
        return Err("usage: cache_output_inventory STORE BUILD_LOG".into());
    }
    let references = output_references(&fs::read_to_string(&args[1]).map_err(|e| e.to_string())?);
    if references.is_empty() {
        return Err("no compilation-cache output remarks in build log".into());
    }
    let up = unsafe { Upstream::load(&upstream_path())? };
    let store = Store::open(&up, Path::new(&args[0]))?;
    for (kind, root) in references {
        println!(
            "{}",
            serde_json::to_string(&store.inventory(kind, root)?).map_err(|e| e.to_string())?
        );
    }
    Ok(())
}

#[test]
fn reads_swift_and_clang_output_remarks_without_inventing_outputs() {
    let log = "note: Using CAS output swiftmodule: 0~abc== (in target 'A')\n\
               note: using CAS output pcm: 0~def==\n\
               note: Using CAS output swiftmodule: 0~abc==\n\
               note: local cache found for key: 0~ghi==\n\
               note: Using CAS output object: missing";
    assert_eq!(
        output_references(log),
        BTreeSet::from([
            ("swiftmodule".into(), "0~abc==".into()),
            ("pcm".into(), "0~def==".into()),
        ])
    );
}
