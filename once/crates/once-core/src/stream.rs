use once_cas::{CacheProvider, Digest};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

use crate::{Error, Result};

/// Bounded pipe size for connecting producers to CAS streaming writes.
/// This keeps subprocess output memory bounded while letting the CAS
/// reader apply backpressure.
pub(crate) const PIPE_CAPACITY: usize = 64 * 1024;

#[derive(Clone, Copy)]
pub(crate) enum Destination {
    Stdout,
    Stderr,
}

/// Forwards a stream to the CAS and optionally mirrors it to stdout or
/// stderr. Parent write failures fail the whole operation; any scratch
/// data left by a cancelled CAS write is ignored by future cache reads.
pub(crate) async fn to_cache<R>(
    mut reader: R,
    destination: Destination,
    cache: &CacheProvider,
    stream_to_parent: bool,
) -> Result<Digest>
where
    R: AsyncRead + Unpin,
{
    let (mut pipe_reader, mut pipe_writer) = tokio::io::duplex(PIPE_CAPACITY);
    let forward = async {
        let mut buf = [0_u8; 4 * 1024];
        loop {
            let n = reader.read(&mut buf).await.map_err(|source| Error::Wait {
                program: "stream".to_string(),
                source,
            })?;
            if n == 0 {
                break;
            }
            write_parent(&buf[..n], destination, stream_to_parent).await?;
            write_pipe(&mut pipe_writer, &buf[..n]).await?;
        }
        shutdown_pipe(&mut pipe_writer).await
    };
    let store = async {
        cache
            .put_stream(&mut pipe_reader)
            .await
            .map_err(Error::from)
    };
    let ((), digest) = tokio::try_join!(forward, store)?;
    Ok(digest)
}

/// Writes bytes to the caller's terminal stream when live mirroring is
/// enabled.
pub(crate) async fn write_parent(
    bytes: &[u8],
    destination: Destination,
    stream_to_parent: bool,
) -> Result<()> {
    if !stream_to_parent {
        return Ok(());
    }
    match destination {
        Destination::Stdout => {
            let mut out = tokio::io::stdout();
            out.write_all(bytes).await.map_err(|source| Error::Wait {
                program: "stdout".to_string(),
                source,
            })?;
            out.flush().await.map_err(|source| Error::Wait {
                program: "stdout".to_string(),
                source,
            })?;
        }
        Destination::Stderr => {
            let mut err = tokio::io::stderr();
            err.write_all(bytes).await.map_err(|source| Error::Wait {
                program: "stderr".to_string(),
                source,
            })?;
            err.flush().await.map_err(|source| Error::Wait {
                program: "stderr".to_string(),
                source,
            })?;
        }
    }
    Ok(())
}

/// Writes a complete chunk into the bounded CAS pipe.
pub(crate) async fn write_pipe<W>(writer: &mut W, bytes: &[u8]) -> Result<()>
where
    W: AsyncWrite + Unpin,
{
    writer.write_all(bytes).await.map_err(|source| Error::Wait {
        program: "stream".to_string(),
        source,
    })
}

/// Flushes and closes the bounded CAS pipe so the reader observes EOF.
pub(crate) async fn shutdown_pipe<W>(writer: &mut W) -> Result<()>
where
    W: AsyncWrite + Unpin,
{
    writer.flush().await.map_err(|source| Error::Wait {
        program: "stream".to_string(),
        source,
    })?;
    writer.shutdown().await.map_err(|source| Error::Wait {
        program: "stream".to_string(),
        source,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use once_cas::{CacheProvider, Cas};
    use tempfile::TempDir;

    fn fresh_cas() -> (TempDir, Cas) {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        (tmp, cas)
    }

    #[tokio::test]
    async fn stream_to_cache_handles_payload_larger_than_pipe_capacity() {
        let (_tmp, cas) = fresh_cas();
        let cache = CacheProvider::Local(cas.clone());
        let payload = vec![b'x'; PIPE_CAPACITY * 2 + 123];

        let digest = to_cache(
            std::io::Cursor::new(payload.clone()),
            Destination::Stdout,
            &cache,
            false,
        )
        .await
        .unwrap();

        assert_eq!(cas.get_blob(&digest).await.unwrap(), payload);
    }
}
