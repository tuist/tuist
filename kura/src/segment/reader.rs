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

const READ_CHUNK_BYTES: usize = 64 * 1024;

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
                            self.remaining = 0;
                            return Poll::Ready(Ok(()));
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
                let mut bytes = vec![0; len];
                let read = read_at(handle.as_std(), &mut bytes, offset).map_err(|error| {
                    format!("failed to read segment at offset {offset}: {error}")
                })?;
                bytes.truncate(read);
                Ok(bytes)
            }));
        }
    }
}

#[cfg(unix)]
fn read_at(file: &std::fs::File, bytes: &mut [u8], offset: u64) -> std::io::Result<usize> {
    use std::os::unix::fs::FileExt;

    file.read_at(bytes, offset)
}

#[cfg(windows)]
fn read_at(file: &std::fs::File, bytes: &mut [u8], offset: u64) -> std::io::Result<usize> {
    use std::os::windows::fs::FileExt;

    file.seek_read(bytes, offset)
}
