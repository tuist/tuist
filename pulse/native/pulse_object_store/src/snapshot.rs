//! Bounded suffix/full reads tied to one strong provider ETag.
use super::*;
use object_store::GetRange;
use std::ops::Range;

#[rustler::nif]
fn snapshot_api_version() -> u32 {
    1
}

#[derive(Debug)]
enum HeaderError {
    TooLarge,
    Changed,
    Invalid,
}

fn validate(
    size: u64,
    range: &Range<u64>,
    tag: &str,
    expected: &str,
    suffix: u64,
    limit: u64,
) -> Result<usize, HeaderError> {
    if size > limit {
        return Err(HeaderError::TooLarge);
    }
    if tag.is_empty() || tag.starts_with("W/") {
        return Err(HeaderError::Invalid);
    }
    if !expected.is_empty() && tag != expected {
        return Err(HeaderError::Changed);
    }
    let start = if suffix == 0 {
        0
    } else {
        size.saturating_sub(suffix)
    };
    if *range != (start..size) {
        return Err(HeaderError::Invalid);
    }
    usize::try_from(size - start).map_err(|_| HeaderError::Invalid)
}

#[allow(clippy::too_many_arguments)]
#[rustler::nif]
fn get_snapshot<'a>(
    env: Env<'a>,
    reference: Term<'a>,
    config: StoreConfig,
    key: String,
    etag: String,
    suffix: u64,
    limit: u64,
    timeout_ms: u64,
) -> NifResult<Atom> {
    if suffix > 1024 * 1024
        || limit == 0
        || limit > 128 * 1024 * 1024
        || timeout_ms == 0
        || timeout_ms > 15_000
    {
        return Err(nif_error("invalid snapshot bounds").into());
    }
    let opts = GetOptions {
        if_match: if etag.is_empty() {
            None
        } else {
            Some(etag.clone())
        },
        range: if suffix == 0 {
            None
        } else {
            Some(GetRange::Suffix(suffix))
        },
        ..GetOptions::default()
    };
    Ok(spawn(env, reference, config, move |store| async move {
        tokio::time::timeout(std::time::Duration::from_millis(timeout_ms), async {
            let obj = store
                .get_opts(&Path::from(key), opts)
                .await
                .map_err(map_object_store_error)?;
            let tag = etag_or_error(obj.meta.e_tag.clone())?;
            let size = obj.meta.size;
            let length = validate(size, &obj.range, &tag, &etag, suffix, limit).map_err(
                |error| match error {
                    HeaderError::TooLarge => Failure::Atom(atoms::response_too_large()),
                    HeaderError::Changed => Failure::Atom(atoms::precondition_failed()),
                    HeaderError::Invalid => {
                        nif_error("snapshot requires a matching range and strong ETag")
                    }
                },
            )?;
            let mut body = OwnedBinary::new(length)
                .ok_or_else(|| nif_error("could not allocate snapshot body"))?;
            fill(obj.into_stream(), body.as_mut_slice())
                .await
                .map_err(nif_error)?;
            Ok(Reply::Snapshot(tag, size, body))
        })
        .await
        .map_err(|_| Failure::Atom(atoms::timeout()))?
    }))
}

async fn fill<S>(mut stream: S, dst: &mut [u8]) -> Result<(), String>
where
    S: futures::Stream<Item = object_store::Result<Bytes>> + Unpin,
{
    let mut offset = 0usize;
    while let Some(chunk) = stream.try_next().await.map_err(|error| error.to_string())? {
        let end = offset
            .checked_add(chunk.len())
            .ok_or("snapshot body length overflow")?;
        if end > dst.len() {
            return Err("snapshot body exceeded declared range".into());
        }
        dst[offset..end].copy_from_slice(&chunk);
        offset = end;
    }
    if offset != dst.len() {
        return Err("snapshot body shorter than declared range".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn streams_require_exact_bytes_eof_and_allow_deadline_cancellation() {
        RUNTIME.block_on(async {
            let mut out = [0u8; 4];
            let chunks = vec![
                Ok(Bytes::from_static(b"ab")),
                Ok(Bytes::new()),
                Ok(Bytes::from_static(b"cd")),
            ];
            fill(futures::stream::iter(chunks), &mut out).await.unwrap();
            assert_eq!(&out, b"abcd");
            assert!(fill(
                futures::stream::iter([Ok(Bytes::from_static(b"abc"))]),
                &mut out
            )
            .await
            .is_err());
            assert!(fill(
                futures::stream::iter([Ok(Bytes::from_static(b"abcde"))]),
                &mut out
            )
            .await
            .is_err());
            let error = ObjectStoreError::Generic {
                store: "test",
                source: "injected failure".into(),
            };
            assert!(fill(futures::stream::iter([Err(error)]), &mut out)
                .await
                .is_err());
            assert!(tokio::time::timeout(
                std::time::Duration::ZERO,
                fill(
                    futures::stream::pending::<object_store::Result<Bytes>>(),
                    &mut out
                )
            )
            .await
            .is_err());
        });
    }

    #[test]
    fn headers_bound_allocation_and_bind_every_response() {
        assert_eq!(validate(100, &(90..100), "\"a\"", "", 10, 100).unwrap(), 10);
        assert_eq!(validate(5, &(0..5), "a", "a", 10, 100).unwrap(), 5);
        assert_eq!(validate(100, &(0..100), "a", "a", 0, 100).unwrap(), 100);
        for (size, range, tag, expected, suffix, limit) in [
            (101, 91..101, "a", "", 10, 100),
            (100, 0..100, "a", "", 10, 100),
            (100, 90..100, "b", "a", 10, 100),
            (100, 90..100, "W/\"a\"", "", 10, 100),
            (100, 90..100, "", "", 10, 100),
            (100, 90..99, "a", "", 10, 100),
        ] {
            assert!(validate(size, &range, tag, expected, suffix, limit).is_err());
        }
    }
}
