//! Minimal protobuf wire-format reader over a borrowed slice.
//!
//! Length-delimited fields come back as sub-slices of the input, which is
//! what lets the NIF hand them to Elixir as sub-binaries without copying.
//! Every read is bounds-checked and returns `None` on malformed input;
//! nothing here allocates or recurses.

pub enum Value<'a> {
    Varint(u64),
    Bytes(&'a [u8]),
    /// A fixed64 payload (`double`, `fixed64`, `sfixed64`), little-endian.
    Fixed64([u8; 8]),
    Fixed32,
}

pub struct Reader<'a> {
    buf: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    pub fn new(buf: &'a [u8]) -> Self {
        Reader { buf, pos: 0 }
    }

    fn varint(&mut self) -> Option<u64> {
        let mut out: u64 = 0;
        for shift in (0..64).step_by(7) {
            let byte = *self.buf.get(self.pos)?;
            self.pos += 1;
            out |= u64::from(byte & 0x7f) << shift;
            if byte & 0x80 == 0 {
                return Some(out);
            }
        }
        None
    }

    /// Whether every byte has been read.
    pub fn is_empty(&self) -> bool {
        self.pos >= self.buf.len()
    }

    /// The next bare varint, as in a packed repeated scalar field.
    pub fn read_varint(&mut self) -> Option<u64> {
        self.varint()
    }

    fn skip(&mut self, n: usize) -> Option<()> {
        self.pos = self.pos.checked_add(n).filter(|p| *p <= self.buf.len())?;
        Some(())
    }

    /// Next `(field_number, value)`. `Some(None)` at end of input, `None`
    /// when the input is malformed (truncated field, bad wire type, or a
    /// length that runs past the end).
    pub fn next_field(&mut self) -> Option<Option<(u64, Value<'a>)>> {
        if self.pos >= self.buf.len() {
            return Some(None);
        }
        let key = self.varint()?;
        let value = match key & 7 {
            0 => Value::Varint(self.varint()?),
            1 => {
                let start = self.pos;
                self.skip(8)?;
                Value::Fixed64(self.buf[start..self.pos].try_into().ok()?)
            }
            2 => {
                let len = usize::try_from(self.varint()?).ok()?;
                let start = self.pos;
                self.skip(len)?;
                Value::Bytes(&self.buf[start..self.pos])
            }
            5 => {
                self.skip(4)?;
                Value::Fixed32
            }
            // 3/4 are deprecated groups; nothing in Loki's schema uses them.
            _ => return None,
        };
        Some(Some((key >> 3, value)))
    }
}

#[cfg(test)]
pub mod encode {
    //! Tiny encoder used only to build test fixtures.

    pub fn varint(out: &mut Vec<u8>, mut v: u64) {
        while v >= 0x80 {
            out.push((v as u8) | 0x80);
            v >>= 7;
        }
        out.push(v as u8);
    }

    pub fn bytes(out: &mut Vec<u8>, field: u64, data: &[u8]) {
        varint(out, (field << 3) | 2);
        varint(out, data.len() as u64);
        out.extend_from_slice(data);
    }

    pub fn uint(out: &mut Vec<u8>, field: u64, v: u64) {
        varint(out, field << 3);
        varint(out, v);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_varint_and_bytes_fields() {
        let mut buf = Vec::new();
        encode::uint(&mut buf, 1, 300);
        encode::bytes(&mut buf, 2, b"hi");
        let mut r = Reader::new(&buf);
        assert!(matches!(
            r.next_field(),
            Some(Some((1, Value::Varint(300))))
        ));
        assert!(matches!(
            r.next_field(),
            Some(Some((2, Value::Bytes(b"hi"))))
        ));
        assert!(matches!(r.next_field(), Some(None)));
    }

    #[test]
    fn rejects_length_past_end() {
        let buf = [0x12, 0x05, b'a'];
        assert!(Reader::new(&buf).next_field().is_none());
    }

    #[test]
    fn rejects_overlong_varint() {
        let buf = [
            0x08, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01,
        ];
        assert!(Reader::new(&buf).next_field().is_none());
    }

    #[test]
    fn rejects_group_wire_types() {
        assert!(Reader::new(&[0x0b]).next_field().is_none());
    }
}
