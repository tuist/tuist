//! Borrow unchanged pages without flattening the complete prepared representation.
use super::{require, Result, MAX_PREPARED};
use std::borrow::Cow;

pub trait Source {
    fn len(&self) -> usize;
    fn chunk_at(&self, offset: usize) -> Result<&[u8]>;

    fn range(&self, offset: usize, size: usize) -> Result<Cow<'_, [u8]>> {
        require(
            offset <= self.len() && size <= self.len() - offset,
            "source range limit",
        )?;
        if size == 0 {
            return Ok(Cow::Borrowed(&[]));
        }
        let first = self.chunk_at(offset)?;
        if first.len() >= size {
            return Ok(Cow::Borrowed(&first[..size]));
        }
        let mut bytes = Vec::with_capacity(size);
        let mut cursor = ViewCursor::new(self, offset, size)?;
        cursor.copy_into(&mut bytes, size)?;
        Ok(Cow::Owned(bytes))
    }
}

impl Source for [u8] {
    fn len(&self) -> usize {
        <[u8]>::len(self)
    }
    fn chunk_at(&self, offset: usize) -> Result<&[u8]> {
        self.get(offset..)
            .ok_or_else(|| "source offset limit".into())
    }
}

#[derive(Default)]
pub struct Segments<'a> {
    parts: Vec<(usize, Cow<'a, [u8]>)>,
    size: usize,
}

impl<'a> Segments<'a> {
    pub fn push(&mut self, bytes: Cow<'a, [u8]>) -> Result<()> {
        require(
            bytes.len() <= MAX_PREPARED - self.size,
            "segment size limit",
        )?;
        if !bytes.is_empty() {
            require(self.parts.len() < 131_072, "segment count limit")?;
            let size = bytes.len();
            self.parts.push((self.size, bytes));
            self.size += size;
        }
        Ok(())
    }

    pub fn into_vec(self) -> Vec<u8> {
        let mut output = Vec::with_capacity(self.size);
        for (_, bytes) in self.parts {
            output.extend_from_slice(&bytes);
        }
        output
    }

    pub fn owned_bytes(&self) -> usize {
        self.parts
            .iter()
            .map(|(_, bytes)| match bytes {
                Cow::Borrowed(_) => 0,
                Cow::Owned(bytes) => bytes.capacity(),
            })
            .sum()
    }
}

impl Source for Segments<'_> {
    fn len(&self) -> usize {
        self.size
    }
    fn chunk_at(&self, offset: usize) -> Result<&[u8]> {
        require(offset < self.size, "source offset limit")?;
        let index = self.parts.partition_point(|(start, _)| *start <= offset) - 1;
        let (start, bytes) = &self.parts[index];
        Ok(&bytes[offset - start..])
    }
}

pub struct ViewCursor<'a, S: Source + ?Sized> {
    source: &'a S,
    pub at: usize,
    pub end: usize,
    window: &'a [u8],
}

impl<'a, S: Source + ?Sized> ViewCursor<'a, S> {
    pub fn new(source: &'a S, offset: usize, size: usize) -> Result<Self> {
        require(
            offset <= source.len() && size <= source.len() - offset,
            "cursor region limit",
        )?;
        Ok(Self {
            source,
            at: offset,
            end: offset + size,
            window: &[],
        })
    }

    fn refill(&mut self) -> Result<()> {
        require(self.at < self.end, "truncated prepared stream")?;
        let bytes = self.source.chunk_at(self.at)?;
        require(!bytes.is_empty(), "empty source chunk")?;
        self.window = &bytes[..bytes.len().min(self.end - self.at)];
        Ok(())
    }

    pub fn region(&mut self, size: usize) -> Result<Self> {
        require(size <= self.end - self.at, "truncated prepared stream")?;
        let cursor = Self::new(self.source, self.at, size)?;
        self.at += size;
        self.window = self.window.get(size..).unwrap_or_default();
        Ok(cursor)
    }

    pub fn read<const N: usize>(&mut self) -> Result<[u8; N]> {
        require(N <= self.end - self.at, "truncated prepared stream")?;
        if self.window.is_empty() && N != 0 {
            self.refill()?;
        }
        let mut bytes = [0; N];
        if self.window.len() >= N {
            bytes.copy_from_slice(&self.window[..N]);
            self.window = &self.window[N..];
            self.at += N;
        } else {
            for byte in &mut bytes {
                *byte = self.byte()?;
            }
        }
        Ok(bytes)
    }

    pub fn byte(&mut self) -> Result<u8> {
        if self.window.is_empty() {
            self.refill()?;
        }
        let value = self.window[0];
        self.window = &self.window[1..];
        self.at += 1;
        Ok(value)
    }

    pub fn u32(&mut self) -> Result<u32> {
        Ok(u32::from_le_bytes(self.read()?))
    }
    pub fn u64(&mut self) -> Result<u64> {
        Ok(u64::from_le_bytes(self.read()?))
    }

    pub fn variable(&mut self) -> Result<u64> {
        let mut value = 0u64;
        for group in 0..10 {
            let byte = self.byte()?;
            require(group < 9 || byte <= 1, "prepared integer overflow")?;
            value |= ((byte & 127) as u64) << (group * 7);
            if byte & 128 == 0 {
                require(group == 0 || byte != 0, "noncanonical prepared integer")?;
                return Ok(value);
            }
        }
        Err("prepared integer group limit".into())
    }

    pub fn copy_into(&mut self, output: &mut Vec<u8>, size: usize) -> Result<()> {
        require(size <= self.end - self.at, "truncated prepared stream")?;
        let end = self.at + size;
        while self.at < end {
            if self.window.is_empty() {
                self.refill()?;
            }
            let count = self.window.len().min(end - self.at);
            output.extend_from_slice(&self.window[..count]);
            self.at += count;
            self.window = &self.window[count..];
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fragmented_cursors_preserve_cross_page_reads_and_regions() {
        let bytes: Vec<_> = (0..251).collect();
        for page in [1, 2, 3, 7, 31, 251] {
            let mut parts = Segments::default();
            for piece in bytes.chunks(page) {
                parts.push(Cow::Borrowed(piece)).unwrap();
            }
            assert_eq!(parts.owned_bytes(), 0);
            assert_eq!(parts.range(5, 233).unwrap().as_ref(), &bytes[5..238]);
            let mut cursor = ViewCursor::new(&parts, 0, bytes.len()).unwrap();
            assert_eq!(
                cursor.u64().unwrap(),
                u64::from_le_bytes(bytes[..8].try_into().unwrap())
            );
            let mut region = cursor.region(17).unwrap();
            assert_eq!(region.read::<17>().unwrap(), &bytes[8..25]);
            assert!(region.byte().is_err());
            assert_eq!(cursor.byte().unwrap(), bytes[25]);
            assert!(cursor.region(usize::MAX).is_err());
            assert!(parts.range(usize::MAX, 1).is_err());
            assert_eq!(parts.into_vec(), bytes);
        }
    }
}
