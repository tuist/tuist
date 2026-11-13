//! Budgeted JSON sink: never expand a large escaped string beyond the ceiling
//! before JsonEncoder can notice TooBig. Used only by bounded trace encodings.
use crate::out::Sink;

pub struct Buffer {
    bytes: Vec<u8>,
    limit: usize,
    overflowed: bool,
}
impl Buffer {
    pub fn new(limit: usize) -> Self {
        Self {
            bytes: Vec::new(),
            limit,
            overflowed: false,
        }
    }
    pub fn finish(self) -> Vec<u8> {
        self.bytes
    }
}
impl Sink for Buffer {
    fn extend(&mut self, bytes: &[u8]) {
        let take = bytes.len().min(self.limit - self.bytes.len());
        self.overflowed |= take < bytes.len();
        self.bytes.extend_from_slice(&bytes[..take]);
    }
    fn push(&mut self, byte: u8) {
        self.extend(&[byte]);
    }
    fn len(&self) -> usize {
        if self.overflowed {
            self.limit + 1
        } else {
            self.bytes.len()
        }
    }
    fn repeat(&mut self, start: usize, end: usize) {
        let take = (end - start).min(self.limit - self.bytes.len());
        self.overflowed |= take < end - start;
        self.bytes.extend_from_within(start..start + take);
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn escaped_string_expansion_stops_at_the_budget() {
        let mut out = Buffer::new(100);
        crate::json_write::write_str(&mut out, &[0; 16_384]);
        assert_eq!(out.len(), 101);
        assert_eq!(out.finish().len(), 100);
    }
}
