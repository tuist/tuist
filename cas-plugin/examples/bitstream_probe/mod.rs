//! Offline, bounded, byte-preserving bitstream field separation.
//! This understands the container spelling, never Swift declaration semantics.
use std::collections::BTreeMap;
use std::sync::Arc;

pub mod grouped;

type Result<T> = std::result::Result<T, String>;
type Key = (i32, i32, u32);
type Abbreviation = Arc<Vec<(u8, u64)>>;
pub const MAX_INPUT: usize = 32 * 1024 * 1024;
pub const MAX_PREPARED: usize = 256 * 1024 * 1024;
const MAX_OPERATIONS: usize = 16 * 1024 * 1024;
const MAX_COLUMNS: usize = 65_536;
const MAX_COLUMN_SLOTS: usize = 1024 * 1024;

fn require(condition: bool, message: &str) -> Result<()> {
    if condition {
        Ok(())
    } else {
        Err(message.into())
    }
}

#[derive(Clone, Copy)]
struct Operation {
    kind: u8,
    width: u8,
    groups: u32,
    value: u64,
}

#[derive(Default)]
struct Column {
    bytes: Vec<u8>,
    previous: u64,
}

impl Column {
    fn append(&mut self, value: u64, delta: bool, compact: bool) -> usize {
        let difference = if delta {
            value.wrapping_sub(self.previous)
        } else {
            value
        };
        self.previous = value;
        if compact {
            write_variable(
                &mut self.bytes,
                if delta {
                    zigzag(difference)
                } else {
                    difference
                },
            )
        } else {
            self.bytes.extend(difference.to_le_bytes());
            8
        }
    }
}

struct Reader<'a> {
    data: &'a [u8],
    position: usize,
    operations: usize,
    abbreviation_operands: usize,
    trace: Vec<Operation>,
    global_abbreviations: BTreeMap<i32, Vec<Abbreviation>>,
    layout: Vec<u8>,
    blobs: Vec<u8>,
    columns: BTreeMap<Key, Column>,
    column_bytes: usize,
    column_cap: u32,
    delta: bool,
    compact_layout: bool,
    compact_columns: bool,
}

impl Reader<'_> {
    fn raw(&mut self, width: u8) -> Result<u64> {
        require(width <= 64, "unsupported integer width")?;
        require(
            self.operations < MAX_OPERATIONS,
            "operation budget exceeded",
        )?;
        self.operations += 1;
        let end = self
            .position
            .checked_add(width as usize)
            .ok_or("bit offset overflow")?;
        require(end <= self.data.len() * 8, "truncated bits")?;
        let mut value = 0u128;
        for (index, byte) in self.data[self.position / 8..end.div_ceil(8)]
            .iter()
            .enumerate()
        {
            value |= (*byte as u128) << (index * 8);
        }
        value >>= self.position % 8;
        self.position = end;
        Ok((value & ((1u128 << width) - 1)) as u64)
    }

    fn bits(&mut self, width: u8) -> Result<u64> {
        let value = self.raw(width)?;
        self.trace.push(Operation {
            kind: 0,
            width,
            groups: 0,
            value,
        });
        Ok(value)
    }

    fn variable(&mut self, width: u8) -> Result<u64> {
        require((2..=32).contains(&width), "unsupported variable width")?;
        let mut value = 0u64;
        for group in 0..64u32 {
            let part = self.raw(width)?;
            let payload = part & ((1 << (width - 1)) - 1);
            let shift = group * (width as u32 - 1);
            require(
                payload == 0 || (shift < 64 && payload <= (u64::MAX >> shift)),
                "integer overflow",
            )?;
            if shift < 64 {
                value |= payload << shift;
            }
            if part >> (width - 1) == 0 {
                self.trace.push(Operation {
                    kind: 1,
                    width,
                    groups: group + 1,
                    value,
                });
                return Ok(value);
            }
        }
        Err("variable integer group limit".into())
    }

    fn align(&mut self) -> Result<()> {
        self.bits(((32 - self.position % 32) % 32) as u8)?;
        Ok(())
    }

    fn finish(&mut self, block: i32, code: i32) -> Result<()> {
        self.layout.extend(block.to_le_bytes());
        self.layout.extend(code.to_le_bytes());
        self.layout.extend((self.trace.len() as u32).to_le_bytes());
        if self.compact_layout {
            let mut index = 0;
            while index < self.trace.len() {
                let operation = self.trace[index];
                let mut end = index + 1;
                while end < self.trace.len()
                    && self.trace[end].kind == operation.kind
                    && self.trace[end].width == operation.width
                    && self.trace[end].groups == operation.groups
                {
                    end += 1;
                }
                self.layout.extend([operation.kind, operation.width]);
                write_variable(&mut self.layout, operation.groups as u64);
                write_variable(&mut self.layout, (end - index) as u64);
                index = end;
            }
        }
        if !self.compact_layout {
            for operation in &self.trace {
                self.layout.extend([operation.kind, operation.width]);
                self.layout.extend(operation.groups.to_le_bytes());
            }
        }
        let (prefix, tail) = self
            .trace
            .split_at(self.trace.len().min(self.column_cap as usize));
        for (index, operation) in prefix.iter().enumerate() {
            if operation.kind != 2 {
                let column = self.columns.entry((block, code, index as u32)).or_default();
                self.column_bytes +=
                    column.append(operation.value, self.delta, self.compact_columns);
            }
        }
        let mut scalars = tail
            .iter()
            .filter(|operation| operation.kind != 2)
            .peekable();
        if scalars.peek().is_some() {
            let column = self
                .columns
                .entry((block, code, self.column_cap))
                .or_default();
            for operation in scalars {
                self.column_bytes +=
                    column.append(operation.value, self.delta, self.compact_columns);
            }
        }
        self.trace.clear();
        require(self.columns.len() <= MAX_COLUMNS, "column limit exceeded")?;
        require(
            self.layout.len() + self.blobs.len() + self.column_bytes + self.columns.len() * 16 + 36
                <= MAX_PREPARED,
            "expansion limit exceeded",
        )
    }

    fn abbreviation(&mut self) -> Result<Abbreviation> {
        let count = self.variable(5)? as usize;
        require(count <= 4096, "abbreviation too large")?;
        self.abbreviation_operands += count;
        require(
            self.abbreviation_operands <= 1024 * 1024,
            "abbreviation budget exceeded",
        )?;
        let mut operands = Vec::with_capacity(count);
        for _ in 0..count {
            operands.push(if self.bits(1)? != 0 {
                (0, self.variable(8)?)
            } else {
                let kind = self.bits(3)? as u8;
                require((1..=5).contains(&kind), "unknown abbreviation operand")?;
                (
                    kind,
                    if kind == 1 || kind == 2 {
                        self.variable(5)?
                    } else {
                        0
                    },
                )
            });
        }
        Ok(Arc::new(operands))
    }

    fn operand(&mut self, (kind, width): (u8, u64)) -> Result<u64> {
        match kind {
            0 => Ok(width),
            1 => self.bits(u8::try_from(width).map_err(|_| "fixed width overflow")?),
            2 => self.variable(u8::try_from(width).map_err(|_| "variable width overflow")?),
            4 => self.bits(6),
            _ => Err("invalid scalar operand".into()),
        }
    }

    fn scan(&mut self, block: i32, end: usize, width: u8, depth: usize) -> Result<()> {
        require(
            depth <= 64 && (2..=32).contains(&width),
            "block depth or width limit",
        )?;
        let mut abbreviations = self
            .global_abbreviations
            .get(&block)
            .cloned()
            .unwrap_or_default();
        let mut selected_block = None;
        while self.position < end {
            let code = self.bits(width)?;
            match code {
                0 => {
                    self.align()?;
                    self.finish(block, -2)?;
                    return require(self.position == end, "block ended at wrong offset");
                }
                1 => {
                    let child = i32::try_from(self.variable(8)?)
                        .map_err(|_| "block identifier overflow")?;
                    let child_width =
                        u8::try_from(self.variable(4)?).map_err(|_| "block width overflow")?;
                    self.align()?;
                    let words = self.bits(32)? as usize;
                    let child_end = self
                        .position
                        .checked_add(words.checked_mul(32).ok_or("block size overflow")?)
                        .ok_or("block end overflow")?;
                    require(child_end <= end, "child exceeds parent block")?;
                    self.finish(block, -1)?;
                    self.scan(child, child_end, child_width, depth + 1)?;
                }
                2 => {
                    let abbreviation = self.abbreviation()?;
                    let target = if block == 0 {
                        self.global_abbreviations
                            .entry(selected_block.ok_or("block-info identifier missing")?)
                            .or_default()
                    } else {
                        &mut abbreviations
                    };
                    require(target.len() < 65_536, "abbreviation count limit")?;
                    target.push(abbreviation);
                    self.finish(block, -3)?;
                }
                3 => {
                    let record = i32::try_from(self.variable(6)?)
                        .map_err(|_| "record identifier overflow")?;
                    let count = self.variable(6)?;
                    require(count <= 1024 * 1024, "record too large")?;
                    for index in 0..count {
                        let value = self.variable(6)?;
                        if block == 0 && record == 1 && index == 0 {
                            selected_block = Some(
                                i32::try_from(value).map_err(|_| "block identifier overflow")?,
                            );
                        }
                    }
                    self.finish(block, record)?;
                }
                _ => {
                    let operands = abbreviations
                        .get((code - 4) as usize)
                        .ok_or("undefined abbreviation")?
                        .clone();
                    let mut first = None;
                    let mut index = 0;
                    while index < operands.len() {
                        match operands[index].0 {
                            3 => {
                                let count = self.variable(6)?;
                                require(count <= 1024 * 1024, "array too large")?;
                                index += 1;
                                let operand =
                                    *operands.get(index).ok_or("missing array operand")?;
                                require(
                                    index + 1 == operands.len(),
                                    "array must end abbreviation",
                                )?;
                                for _ in 0..count {
                                    let value = self.operand(operand)?;
                                    first.get_or_insert(value);
                                }
                            }
                            5 => {
                                let size = usize::try_from(self.variable(6)?)
                                    .map_err(|_| "blob size overflow")?;
                                self.align()?;
                                let finish = (self.position / 8)
                                    .checked_add(size)
                                    .ok_or("blob end overflow")?;
                                require(finish <= end / 8, "blob exceeds block")?;
                                self.blobs
                                    .extend_from_slice(&self.data[self.position / 8..finish]);
                                self.position = finish * 8;
                                self.trace.push(Operation {
                                    kind: 2,
                                    width: 0,
                                    groups: size as u32,
                                    value: 0,
                                });
                                self.align()?;
                            }
                            _ => {
                                let value = self.operand(operands[index])?;
                                first.get_or_insert(value);
                            }
                        }
                        index += 1;
                    }
                    self.finish(
                        block,
                        i32::try_from(first.ok_or("record code missing")?)
                            .map_err(|_| "record code overflow")?,
                    )?;
                }
            }
            require(self.position <= end, "record exceeds block")?;
        }
        require(depth == 0, "missing end-block marker")
    }
}

pub fn prepare(data: &[u8], delta: bool, column_cap: u32) -> Result<Vec<u8>> {
    prepare_compact(data, delta, column_cap, false, false)
}

pub fn prepare_compact(
    data: &[u8],
    delta: bool,
    column_cap: u32,
    compact_layout: bool,
    compact_columns: bool,
) -> Result<Vec<u8>> {
    require(
        data.len() <= MAX_INPUT && data.len() >= 4,
        "input size limit",
    )?;
    require(column_cap <= 1024, "column operand limit")?;
    require(
        matches!(
            &data[..4],
            [0xe2, 0x9c, 0xa8, 0x0e] | b"CPCH" | b"BC\xc0\xde"
        ),
        "unsupported bitstream signature",
    )?;
    let mut reader = Reader {
        data,
        position: 0,
        operations: 0,
        abbreviation_operands: 0,
        trace: Vec::new(),
        global_abbreviations: BTreeMap::new(),
        layout: Vec::new(),
        blobs: Vec::new(),
        columns: BTreeMap::new(),
        column_bytes: 0,
        column_cap,
        delta,
        compact_layout,
        compact_columns,
    };
    reader.bits(32)?;
    reader.finish(-1, -4)?;
    reader.scan(-1, data.len() * 8, 2, 0)?;
    require(
        reader.position == data.len() * 8 && reader.trace.is_empty(),
        "unconsumed input",
    )?;
    let mut output = Vec::with_capacity(
        36 + reader.columns.len() * 16
            + reader.layout.len()
            + reader.blobs.len()
            + reader.column_bytes,
    );
    output.extend(if compact_layout || compact_columns {
        b"BCOL0002"
    } else {
        b"BCOL0001"
    });
    output.extend((data.len() as u64).to_le_bytes());
    for size in [
        reader.layout.len(),
        reader.blobs.len(),
        reader.columns.len(),
        column_cap as usize,
        delta as usize | (usize::from(compact_layout) << 1) | (usize::from(compact_columns) << 2),
    ] {
        output.extend((size as u32).to_le_bytes());
    }
    for ((block, code, operand), column) in &reader.columns {
        output.extend(block.to_le_bytes());
        output.extend(code.to_le_bytes());
        output.extend(operand.to_le_bytes());
        output.extend((column.bytes.len() as u32).to_le_bytes());
    }
    output.extend(reader.layout);
    output.extend(reader.blobs);
    for column in reader.columns.into_values() {
        output.extend(column.bytes);
    }
    require(output.len() <= MAX_PREPARED, "prepared size limit")?;
    Ok(output)
}

struct Cursor<'a> {
    data: &'a [u8],
    at: usize,
}

fn zigzag(value: u64) -> u64 {
    (value << 1) ^ ((value as i64 >> 63) as u64)
}

fn unzigzag(value: u64) -> u64 {
    (value >> 1) ^ 0u64.wrapping_sub(value & 1)
}

fn write_variable(output: &mut Vec<u8>, mut value: u64) -> usize {
    let start = output.len();
    while value >= 128 {
        output.push(value as u8 | 128);
        value >>= 7;
    }
    output.push(value as u8);
    output.len() - start
}

fn prepared_version(input: &mut Cursor<'_>) -> Result<bool> {
    match input.take(8)? {
        b"BCOL0001" => Ok(false),
        b"BCOL0002" => Ok(true),
        _ => Err("unknown prepared format".into()),
    }
}

impl<'a> Cursor<'a> {
    fn take(&mut self, size: usize) -> Result<&'a [u8]> {
        let end = self.at.checked_add(size).ok_or("cursor overflow")?;
        let bytes = self
            .data
            .get(self.at..end)
            .ok_or("truncated prepared stream")?;
        self.at = end;
        Ok(bytes)
    }
    fn u32(&mut self) -> Result<u32> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().unwrap()))
    }
    fn u64(&mut self) -> Result<u64> {
        Ok(u64::from_le_bytes(self.take(8)?.try_into().unwrap()))
    }
    fn variable(&mut self) -> Result<u64> {
        let mut value = 0u64;
        for group in 0..10 {
            let byte = self.take(1)?[0];
            require(group < 9 || byte <= 1, "prepared integer overflow")?;
            value |= ((byte & 127) as u64) << (group * 7);
            if byte & 128 == 0 {
                require(group == 0 || byte != 0, "noncanonical prepared integer")?;
                return Ok(value);
            }
        }
        Err("prepared integer group limit".into())
    }
}

#[derive(Default)]
struct Writer {
    data: Vec<u8>,
    pending: u128,
    count: u8,
    limit: usize,
}
impl Writer {
    fn bits(&mut self, value: u64, width: u8) -> Result<()> {
        require(
            width <= 64 && (width == 64 || value < (1u64 << width)),
            "invalid fixed value",
        )?;
        self.pending |= (value as u128) << self.count;
        self.count += width;
        while self.count >= 8 {
            require(self.data.len() < self.limit, "restored size limit")?;
            self.data.push(self.pending as u8);
            self.pending >>= 8;
            self.count -= 8;
        }
        Ok(())
    }
}

pub fn restore(data: &[u8], expected_size: usize) -> Result<Vec<u8>> {
    require(
        data.len() <= MAX_PREPARED && expected_size <= MAX_INPUT,
        "restore size limit",
    )?;
    let mut input = Cursor { data, at: 0 };
    let compact_version = prepared_version(&mut input)?;
    require(
        input.u64()? == expected_size as u64,
        "restored size mismatch",
    )?;
    let layout_size = input.u32()? as usize;
    let blob_size = input.u32()? as usize;
    let column_count = input.u32()? as usize;
    let column_cap = input.u32()?;
    let flags = input.u32()?;
    let delta = flags & 1;
    let compact_layout = flags & 2 != 0;
    let compact_columns = flags & 4 != 0;
    require(
        column_count <= MAX_COLUMNS
            && column_cap <= 1024
            && flags <= if compact_version { 7 } else { 1 },
        "invalid prepared parameters",
    )?;
    let mut descriptors = Vec::new();
    for _ in 0..column_count {
        let key = (input.u32()? as i32, input.u32()? as i32, input.u32()?);
        let size = input.u32()? as usize;
        require(
            compact_columns || size.is_multiple_of(8),
            "invalid column size",
        )?;
        descriptors.push((key, size));
    }
    let mut layout = Cursor {
        data: input.take(layout_size)?,
        at: 0,
    };
    let mut blobs = Cursor {
        data: input.take(blob_size)?,
        at: 0,
    };
    let mut columns: BTreeMap<(i32, i32), Vec<Option<(Cursor<'_>, u64)>>> = BTreeMap::new();
    let mut slots = 0;
    for (key, size) in descriptors {
        require(key.2 <= column_cap, "invalid column index")?;
        let row = columns.entry((key.0, key.1)).or_default();
        let length = key.2 as usize + 1;
        if row.len() < length {
            slots += length - row.len();
            require(slots <= MAX_COLUMN_SLOTS, "column slot limit exceeded")?;
            row.resize_with(length, || None);
        }
        let column = &mut row[key.2 as usize];
        require(column.is_none(), "duplicate column")?;
        *column = Some((
            Cursor {
                data: input.take(size)?,
                at: 0,
            },
            0,
        ));
    }
    require(input.at == data.len(), "trailing prepared bytes")?;
    let mut writer = Writer {
        data: Vec::with_capacity(expected_size),
        limit: expected_size,
        ..Default::default()
    };
    let mut operations = 0;
    while layout.at < layout.data.len() {
        let block = layout.u32()? as i32;
        let code = layout.u32()? as i32;
        let count = layout.u32()? as usize;
        operations += count;
        require(operations <= MAX_OPERATIONS, "restore operation budget")?;
        let mut row = columns.get_mut(&(block, code));
        let (mut kind, mut width, mut groups, mut left) = (0, 0, 0, 0usize);
        for index in 0..count {
            if compact_layout {
                if left == 0 {
                    kind = layout.take(1)?[0];
                    width = layout.take(1)?[0];
                    groups =
                        u32::try_from(layout.variable()?).map_err(|_| "layout group overflow")?;
                    left =
                        usize::try_from(layout.variable()?).map_err(|_| "layout run overflow")?;
                    require(left > 0 && left <= count - index, "invalid layout run")?;
                }
                left -= 1;
            } else {
                kind = layout.take(1)?[0];
                width = layout.take(1)?[0];
                groups = layout.u32()?;
            }
            if kind == 2 {
                require(width == 0 && writer.count == 0, "invalid blob layout")?;
                require(
                    groups as usize <= expected_size.saturating_sub(writer.data.len()),
                    "blob output limit",
                )?;
                writer.data.extend_from_slice(blobs.take(groups as usize)?);
                continue;
            }
            let (column, previous) = row
                .as_mut()
                .and_then(|row| row.get_mut(index.min(column_cap as usize)))
                .and_then(Option::as_mut)
                .ok_or("missing column")?;
            let mut value = if compact_columns {
                column.variable()?
            } else {
                column.u64()?
            };
            if compact_columns && delta != 0 {
                value = unzigzag(value);
            }
            if delta != 0 {
                value = previous.wrapping_add(value);
            }
            *previous = value;
            match kind {
                0 => {
                    require(groups == 0, "invalid fixed spelling")?;
                    writer.bits(value, width)?;
                }
                1 => {
                    require(
                        (2..=32).contains(&width) && (1..=64).contains(&groups),
                        "invalid variable spelling",
                    )?;
                    for group in 0..groups {
                        let mut part = value & ((1 << (width - 1)) - 1);
                        value >>= width - 1;
                        if group + 1 < groups {
                            part |= 1 << (width - 1);
                        }
                        writer.bits(part, width)?;
                    }
                    require(value == 0, "variable value exceeds spelling")?;
                }
                _ => return Err("unknown layout operation".into()),
            }
        }
    }
    require(
        writer.count == 0 && writer.data.len() == expected_size,
        "incomplete restored output",
    )?;
    require(
        blobs.at == blobs.data.len()
            && columns
                .values()
                .flatten()
                .flatten()
                .all(|(column, _)| column.at == column.data.len()),
        "unconsumed prepared data",
    )?;
    Ok(writer.data)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> Vec<u8> {
        let mut writer = Writer {
            limit: 1024,
            ..Default::default()
        };
        for (value, width) in [
            (0x0ea89ce2, 32),
            (3, 2),
            (7, 6),
            (3, 6),
            (1, 6),
            (40, 6),
            (31, 6),
            (40, 6),
            (31, 6),
            (0, 2),
        ] {
            writer.bits(value, width).unwrap();
        }
        let padding = (32 - ((writer.data.len() * 8 + writer.count as usize) % 32)) % 32;
        writer.bits(0, padding as u8).unwrap();
        writer.data
    }

    #[test]
    fn compact_representations_preserve_spelling_and_reject_malformed_runs() {
        let mut bytes = fixture();
        *bytes.last_mut().unwrap() = 0xa5;
        for delta in [false, true] {
            for compact_layout in [false, true] {
                for compact_columns in [false, true] {
                    for cap in [0, 32] {
                        let prepared =
                            prepare_compact(&bytes, delta, cap, compact_layout, compact_columns)
                                .unwrap();
                        assert_eq!(restore(&prepared, bytes.len()).unwrap(), bytes);
                        for end in 0..prepared.len() {
                            assert!(restore(&prepared[..end], bytes.len()).is_err());
                        }
                        for index in 0..prepared.len() {
                            let mut changed = prepared.clone();
                            changed[index] ^= 0xff;
                            let _ = restore(&changed, bytes.len());
                        }
                    }
                }
            }
        }
        let prepared = prepare_compact(&bytes, true, 32, true, true).unwrap();
        let count = u32::from_le_bytes(prepared[24..28].try_into().unwrap()) as usize;
        let first_run = 36 + count * 16 + 15;
        for invalid in [0, 2] {
            let mut changed = prepared.clone();
            changed[first_run] = invalid;
            assert_eq!(
                restore(&changed, bytes.len()).unwrap_err(),
                "invalid layout run"
            );
        }
    }

    #[test]
    fn compact_integer_extremes_round_trip_without_overflow() {
        for value in [
            0,
            1,
            127,
            128,
            255,
            u32::MAX as u64,
            1 << 63,
            u64::MAX - 1,
            u64::MAX,
        ] {
            assert_eq!(unzigzag(zigzag(value)), value);
            let mut bytes = Vec::new();
            let size = write_variable(&mut bytes, value);
            assert_eq!(size, bytes.len());
            assert!(size <= 10);
            assert_eq!(
                Cursor {
                    data: &bytes,
                    at: 0
                }
                .variable()
                .unwrap(),
                value
            );
        }
        for bytes in [vec![0x80], vec![0x80, 0], vec![0xff; 10], vec![0x80; 11]] {
            assert!(Cursor {
                data: &bytes,
                at: 0
            }
            .variable()
            .is_err());
        }
    }

    #[test]
    fn preserves_records_padding_and_variable_integer_spelling() {
        let bytes = fixture();
        for delta in [false, true] {
            for cap in [0, 8, 32] {
                let prepared = prepare(&bytes, delta, cap).unwrap();
                assert_eq!(restore(&prepared, bytes.len()).unwrap(), bytes);
            }
        }
    }

    #[test]
    fn rejects_truncation_wrong_sizes_and_unconsumed_data() {
        let bytes = fixture();
        let prepared = prepare(&bytes, true, 32).unwrap();
        for end in 0..prepared.len() {
            assert!(restore(&prepared[..end], bytes.len()).is_err());
        }
        assert!(restore(&prepared, bytes.len() + 1).is_err());
        let mut extra = prepared.clone();
        extra.push(0);
        assert!(restore(&extra, bytes.len()).is_err());
        assert!(prepare(b"unknown", true, 32).is_err());
    }

    #[test]
    fn rejects_a_child_without_its_end_marker() {
        let mut writer = Writer {
            limit: 1024,
            ..Default::default()
        };
        for (value, width) in [(0x0ea89ce2, 32), (1, 2), (8, 8), (2, 4), (0, 18), (0, 32)] {
            writer.bits(value, width).unwrap();
        }
        assert!(prepare(&writer.data, true, 32).is_err());
    }

    #[test]
    fn malformed_mutations_never_panic() {
        let bytes = fixture();
        let prepared = prepare(&bytes, true, 32).unwrap();
        for index in 0..prepared.len() {
            let mut changed = prepared.clone();
            changed[index] ^= 0xff;
            let _ = restore(&changed, bytes.len());
        }
        for index in 4..bytes.len() {
            let mut changed = bytes.clone();
            changed[index] ^= 0xff;
            let _ = prepare(&changed, true, 32);
        }
    }
}
