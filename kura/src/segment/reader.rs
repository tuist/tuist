use std::{
    pin::Pin,
    sync::Arc,
    task::{Context, Poll},
};

use tokio::{
    io::{self, AsyncRead, ReadBuf},
    task::JoinHandle,
};

use crate::io::PersistentFile;

const READ_CHUNK_BYTES: usize = 512 * 1024;

pub struct SegmentReader {
    handle: Arc<PersistentFile>,
    offset: u64,
    remaining: u64,
    pending_read: Option<JoinHandle<Result<Vec<u8>, String>>>,
    buffered: Option<Vec<u8>>,
    buffered_offset: usize,
}

impl SegmentReader {
    pub fn new(handle: Arc<PersistentFile>, offset: u64, remaining: u64) -> Self {
        Self {
            handle,
            offset,
            remaining,
            pending_read: None,
            buffered: None,
            buffered_offset: 0,
        }
    }

    pub async fn read_chunk_owned(&mut self, max_bytes: usize) -> io::Result<Vec<u8>> {
        if max_bytes == 0 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "segment read chunk size must be non-zero",
            ));
        }
        if self.pending_read.is_some() || self.buffered.is_some() {
            return Err(io::Error::other(
                "owned segment reads cannot follow a pending buffered read",
            ));
        }
        if self.remaining == 0 {
            return Ok(Vec::new());
        }

        let len = self
            .remaining
            .min(max_bytes as u64)
            .min(READ_CHUNK_BYTES as u64) as usize;
        let offset = self.offset;
        let handle = self.handle.clone();
        let bytes = tokio::task::spawn_blocking(move || read_chunk(handle, offset, len))
            .await
            .map_err(|error| io::Error::other(format!("segment read task failed: {error}")))?
            .map_err(io::Error::other)?;
        if bytes.is_empty() {
            return Err(truncated_segment_error(self.remaining));
        }
        self.offset = self.offset.saturating_add(bytes.len() as u64);
        self.remaining = self.remaining.saturating_sub(bytes.len() as u64);
        Ok(bytes)
    }
}

impl AsyncRead for SegmentReader {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        loop {
            if self.remaining == 0 {
                return Poll::Ready(Ok(()));
            }

            if let Some(buffered) = self.buffered.take() {
                let remaining_buffer = &buffered[self.buffered_offset..];
                let copy_len = remaining_buffer.len().min(buf.remaining());
                buf.put_slice(&remaining_buffer[..copy_len]);
                self.buffered_offset += copy_len;
                self.offset += copy_len as u64;
                self.remaining = self.remaining.saturating_sub(copy_len as u64);

                if self.buffered_offset < buffered.len() {
                    self.buffered = Some(buffered);
                } else {
                    self.buffered_offset = 0;
                }

                return Poll::Ready(Ok(()));
            }

            if let Some(read) = &mut self.pending_read {
                match Pin::new(read).poll(cx) {
                    Poll::Pending => return Poll::Pending,
                    Poll::Ready(Ok(Ok(bytes))) => {
                        self.pending_read = None;
                        if bytes.is_empty() {
                            // EOF before `remaining` bytes: the backing file is
                            // shorter than the artifact's manifested length (the
                            // never-truncated invariant was violated). Fail loudly
                            // instead of streaming a short body as if complete —
                            // a silent short body reads as a corrupt/undecodable
                            // response to peers. The pre-serve length guard in
                            // `Store::open_manifest_reader_with_range` normally
                            // 404s these before any bytes are sent; this catches a
                            // file truncated mid-stream.
                            return Poll::Ready(Err(truncated_segment_error(self.remaining)));
                        }
                        self.buffered = Some(bytes);
                        self.buffered_offset = 0;
                    }
                    Poll::Ready(Ok(Err(error))) => {
                        self.pending_read = None;
                        return Poll::Ready(Err(io::Error::other(error)));
                    }
                    Poll::Ready(Err(error)) => {
                        self.pending_read = None;
                        return Poll::Ready(Err(io::Error::other(format!(
                            "segment read task failed: {error}"
                        ))));
                    }
                }
                continue;
            }

            let len = self.remaining.min(READ_CHUNK_BYTES as u64) as usize;
            let offset = self.offset;
            let handle = self.handle.clone();
            self.pending_read = Some(tokio::task::spawn_blocking(move || {
                read_chunk(handle, offset, len)
            }));
        }
    }
}

fn read_chunk(handle: Arc<PersistentFile>, offset: u64, len: usize) -> Result<Vec<u8>, String> {
    read_chunk_from_file(handle.as_std(), offset, len)
}

#[cfg(unix)]
fn read_chunk_from_file(file: &std::fs::File, offset: u64, len: usize) -> Result<Vec<u8>, String> {
    let mut bytes = Vec::with_capacity(len);
    rustix::io::pread(file, rustix::buffer::spare_capacity(&mut bytes), offset)
        .map_err(|error| format!("failed to read segment at offset {offset}: {error}"))?;
    Ok(bytes)
}

#[cfg(windows)]
fn read_chunk_from_file(file: &std::fs::File, offset: u64, len: usize) -> Result<Vec<u8>, String> {
    let mut bytes = vec![0; len];
    let read = read_at(file, &mut bytes, offset)
        .map_err(|error| format!("failed to read segment at offset {offset}: {error}"))?;
    bytes.truncate(read);
    Ok(bytes)
}

fn truncated_segment_error(remaining: u64) -> io::Error {
    io::Error::new(
        io::ErrorKind::UnexpectedEof,
        format!("segment truncated: {remaining} bytes short of the artifact's manifested length"),
    )
}

#[cfg(windows)]
fn read_at(file: &std::fs::File, bytes: &mut [u8], offset: u64) -> std::io::Result<usize> {
    use std::os::windows::fs::FileExt;

    file.seek_read(bytes, offset)
}

#[cfg(all(test, unix))]
mod tests {
    use std::{os::unix::fs::FileExt as _, time::Duration};

    use super::*;

    #[test]
    #[ignore = "performance benchmark run by autoresearch.sh"]
    fn segment_reader_uninitialized_chunk_benchmark() {
        const SAMPLE_BYTES: u64 = 512 * 1_024 * 1_024;
        const CHUNK_BYTES: usize = 512 * 1_024;
        const SAMPLE_COUNT: usize = 10;

        fn initialized_read(
            file: &std::fs::File,
            offset: u64,
            len: usize,
        ) -> Result<Vec<u8>, String> {
            let mut bytes = vec![0; len];
            let read = file
                .read_at(&mut bytes, offset)
                .map_err(|error| format!("failed to read benchmark chunk: {error}"))?;
            bytes.truncate(read);
            Ok(bytes)
        }

        fn measure(file: &std::fs::File, uninitialized: bool) -> Duration {
            let started_at = std::time::Instant::now();
            let mut offset = 0_u64;
            while offset < SAMPLE_BYTES {
                let len = usize::try_from((SAMPLE_BYTES - offset).min(CHUNK_BYTES as u64))
                    .expect("benchmark chunk length fits usize");
                let bytes = if uninitialized {
                    read_chunk_from_file(file, offset, len)
                } else {
                    initialized_read(file, offset, len)
                }
                .expect("benchmark chunk read");
                assert_eq!(bytes.len(), len);
                std::hint::black_box(bytes.as_ptr());
                offset += bytes.len() as u64;
            }
            started_at.elapsed()
        }

        let file = tempfile::tempfile().expect("create sparse benchmark file");
        file.set_len(SAMPLE_BYTES)
            .expect("size sparse benchmark file");
        let mut speedups = Vec::with_capacity(SAMPLE_COUNT - 1);
        let mut baseline_throughputs = Vec::with_capacity(SAMPLE_COUNT - 1);
        let mut candidate_throughputs = Vec::with_capacity(SAMPLE_COUNT - 1);
        for sample in 0..SAMPLE_COUNT {
            let (baseline_elapsed, candidate_elapsed) = if sample % 2 == 0 {
                (measure(&file, false), measure(&file, true))
            } else {
                let candidate_elapsed = measure(&file, true);
                let baseline_elapsed = measure(&file, false);
                (baseline_elapsed, candidate_elapsed)
            };
            if sample > 0 {
                let mebibytes = SAMPLE_BYTES as f64 / (1_024.0 * 1_024.0);
                baseline_throughputs.push(mebibytes / baseline_elapsed.as_secs_f64());
                candidate_throughputs.push(mebibytes / candidate_elapsed.as_secs_f64());
                speedups.push(baseline_elapsed.as_secs_f64() / candidate_elapsed.as_secs_f64());
            }
        }
        speedups.sort_by(f64::total_cmp);
        baseline_throughputs.sort_by(f64::total_cmp);
        candidate_throughputs.sort_by(f64::total_cmp);
        println!(
            "METRIC segment_read_uninitialized_speedup_ratio={:.6}",
            speedups[speedups.len() / 2]
        );
        println!(
            "METRIC baseline_mebibytes_per_second={:.3}",
            baseline_throughputs[baseline_throughputs.len() / 2]
        );
        println!(
            "METRIC candidate_mebibytes_per_second={:.3}",
            candidate_throughputs[candidate_throughputs.len() / 2]
        );
    }
}
