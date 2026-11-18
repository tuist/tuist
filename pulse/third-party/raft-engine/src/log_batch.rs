// Copyright (c) 2017-present, PingCAP, Inc. Licensed under Apache-2.0.

use std::fmt::Debug;
use std::io::BufRead;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::{mem, u64};

use byteorder::{BigEndian, LittleEndian, ReadBytesExt, WriteBytesExt};
use log::error;
use num_derive::FromPrimitive;
use num_traits::FromPrimitive;
use protobuf::Message;

use crate::codec::{self, NumberEncoder};
use crate::memtable::EntryIndex;
use crate::metrics::StopWatch;
use crate::pipe_log::{FileBlockHandle, FileId, LogFileContext, ReactiveBytes};
use crate::util::{crc32, lz4};
use crate::{perf_context, Error, Result};

pub(crate) const LOG_BATCH_HEADER_LEN: usize = 16;
pub(crate) const LOG_BATCH_CHECKSUM_LEN: usize = 4;

const TYPE_ENTRIES: u8 = 0x01;
const TYPE_COMMAND: u8 = 0x02;
const TYPE_KV: u8 = 0x3;

const CMD_CLEAN: u8 = 0x01;
const CMD_COMPACT: u8 = 0x02;

const DEFAULT_LOG_ITEM_BATCH_CAP: usize = 64;
const MAX_LOG_BATCH_BUFFER_CAP: usize = 8 * 1024 * 1024;
// 2GiB, The maximum content length accepted by lz4 compression.
const MAX_LOG_ENTRIES_SIZE_PER_BATCH: usize = i32::MAX as usize;

/// `MessageExt` trait allows for probing log index from a specific type of
/// protobuf messages.
pub trait MessageExt: Send + Sync {
    type Entry: Message + Clone + PartialEq;

    fn index(e: &Self::Entry) -> u64;
}

/// Types of compression.
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum CompressionType {
    None = 0,
    Lz4 = 1,
}

impl CompressionType {
    pub fn from_u8(t: u8) -> Result<Self> {
        if t <= CompressionType::Lz4 as u8 {
            Ok(unsafe { mem::transmute(t) })
        } else {
            Err(Error::Corruption(format!(
                "Unrecognized compression type: {t}"
            )))
        }
    }

    pub fn to_u8(self) -> u8 {
        self as u8
    }
}

type SliceReader<'a> = &'a [u8];

// Format:
// { count | first index | [ tail offsets ] }
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EntryIndexes(pub Vec<EntryIndex>);

impl EntryIndexes {
    pub fn decode(buf: &mut SliceReader, entries_size: &mut u32) -> Result<Self> {
        let mut count = codec::decode_var_u64(buf)?;
        let mut entry_indexes = Vec::with_capacity(count as usize);
        let mut index = 0;
        if count > 0 {
            index = codec::decode_var_u64(buf)?;
        }
        while count > 0 {
            let t = codec::decode_var_u64(buf)?;
            let entry_len = (t as u32) - *entries_size;
            let entry_index = EntryIndex {
                index,
                entry_offset: *entries_size,
                entry_len,
                ..Default::default()
            };
            *entries_size += entry_len;
            entry_indexes.push(entry_index);
            index += 1;
            count -= 1;
        }
        Ok(Self(entry_indexes))
    }

    pub fn encode(&self, buf: &mut Vec<u8>) -> Result<()> {
        let count = self.0.len() as u64;
        buf.encode_var_u64(count)?;
        if count > 0 {
            buf.encode_var_u64(self.0[0].index)?;
        }
        for ei in self.0.iter() {
            buf.encode_var_u64((ei.entry_offset + ei.entry_len) as u64)?;
        }
        Ok(())
    }

    fn approximate_size(&self) -> usize {
        8 /*count*/ + if self.0.is_empty() { 0 } else { 8 } /*first index*/ + 8 /*tail offset*/ * self.0.len()
    }
}

// Format:
// { type | (index) }
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Command {
    Clean,
    Compact { index: u64 },
}

impl Command {
    pub fn encode(&self, vec: &mut Vec<u8>) {
        match *self {
            Command::Clean => {
                vec.push(CMD_CLEAN);
            }
            Command::Compact { index } => {
                vec.push(CMD_COMPACT);
                vec.encode_var_u64(index).unwrap();
            }
        }
    }

    pub fn decode(buf: &mut SliceReader) -> Result<Command> {
        let command_type = codec::read_u8(buf)?;
        match command_type {
            CMD_CLEAN => Ok(Command::Clean),
            CMD_COMPACT => {
                let index = codec::decode_var_u64(buf)?;
                Ok(Command::Compact { index })
            }
            _ => Err(Error::Corruption(format!(
                "Unrecognized command type: {command_type}"
            ))),
        }
    }

    fn approximate_size(&self) -> usize {
        match &self {
            Command::Clean => 1,              /* type */
            Command::Compact { .. } => 1 + 8, /* type + index */
        }
    }
}

#[repr(u8)]
#[derive(Debug, PartialEq, Eq, Copy, Clone)]
pub enum OpType {
    Put = 1,
    Del = 2,
}

impl OpType {
    pub fn from_u8(t: u8) -> Result<Self> {
        if t <= OpType::Del as u8 {
            Ok(unsafe { mem::transmute(t) })
        } else {
            Err(Error::Corruption(format!("Unrecognized op type: {t}")))
        }
    }

    pub fn to_u8(self) -> u8 {
        self as u8
    }
}

// Format:
// { op_type | key len | key | ( value len | value ) }
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KeyValue {
    pub op_type: OpType,
    pub key: Vec<u8>,
    pub value: Option<Vec<u8>>,
    pub file_id: Option<FileId>,
}

impl KeyValue {
    pub fn new(op_type: OpType, key: Vec<u8>, value: Option<Vec<u8>>) -> KeyValue {
        KeyValue {
            op_type,
            key,
            value,
            file_id: None,
        }
    }

    pub fn decode(buf: &mut SliceReader) -> Result<KeyValue> {
        let op_type = OpType::from_u8(codec::read_u8(buf)?)?;
        let k_len = codec::decode_var_u64(buf)? as usize;
        let key = &buf[..k_len];
        buf.consume(k_len);
        match op_type {
            OpType::Put => {
                let v_len = codec::decode_var_u64(buf)? as usize;
                let value = &buf[..v_len];
                buf.consume(v_len);
                Ok(KeyValue::new(
                    OpType::Put,
                    key.to_vec(),
                    Some(value.to_vec()),
                ))
            }
            OpType::Del => Ok(KeyValue::new(OpType::Del, key.to_vec(), None)),
        }
    }

    pub fn encode(&self, vec: &mut Vec<u8>) -> Result<()> {
        vec.push(self.op_type.to_u8());
        vec.encode_var_u64(self.key.len() as u64)?;
        vec.extend_from_slice(self.key.as_slice());
        match self.op_type {
            OpType::Put => {
                vec.encode_var_u64(self.value.as_ref().unwrap().len() as u64)?;
                vec.extend_from_slice(self.value.as_ref().unwrap().as_slice());
            }
            OpType::Del => {}
        }
        Ok(())
    }

    fn approximate_size(&self) -> usize {
        1 /*op*/ + 8 /*k_len*/ + self.key.len() + 8 /*v_len*/ + self.value.as_ref().map_or_else(|| 0, |v| v.len())
    }
}

// Format:
// { 8 byte region id | 1 byte type | item }
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LogItem {
    pub raft_group_id: u64,
    pub content: LogItemContent,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LogItemContent {
    EntryIndexes(EntryIndexes),
    Command(Command),
    Kv(KeyValue),
}

impl LogItem {
    pub fn new_entry_indexes(raft_group_id: u64, entry_indexes: Vec<EntryIndex>) -> LogItem {
        LogItem {
            raft_group_id,
            content: LogItemContent::EntryIndexes(EntryIndexes(entry_indexes)),
        }
    }

    pub fn new_command(raft_group_id: u64, command: Command) -> LogItem {
        LogItem {
            raft_group_id,
            content: LogItemContent::Command(command),
        }
    }

    pub fn new_kv(
        raft_group_id: u64,
        op_type: OpType,
        key: Vec<u8>,
        value: Option<Vec<u8>>,
    ) -> LogItem {
        LogItem {
            raft_group_id,
            content: LogItemContent::Kv(KeyValue::new(op_type, key, value)),
        }
    }

    pub fn encode(&self, buf: &mut Vec<u8>) -> Result<()> {
        buf.encode_var_u64(self.raft_group_id)?;
        match &self.content {
            LogItemContent::EntryIndexes(entry_indexes) => {
                buf.push(TYPE_ENTRIES);
                entry_indexes.encode(buf)?;
            }
            LogItemContent::Command(command) => {
                buf.push(TYPE_COMMAND);
                command.encode(buf);
            }
            LogItemContent::Kv(kv) => {
                buf.push(TYPE_KV);
                kv.encode(buf)?;
            }
        }
        Ok(())
    }

    pub fn decode(buf: &mut SliceReader, entries_size: &mut u32) -> Result<LogItem> {
        let raft_group_id = codec::decode_var_u64(buf)?;
        let item_type = buf.read_u8()?;
        let content = match item_type {
            TYPE_ENTRIES => {
                let entry_indexes = EntryIndexes::decode(buf, entries_size)?;
                LogItemContent::EntryIndexes(entry_indexes)
            }
            TYPE_COMMAND => {
                let cmd = Command::decode(buf)?;
                LogItemContent::Command(cmd)
            }
            TYPE_KV => {
                let kv = KeyValue::decode(buf)?;
                LogItemContent::Kv(kv)
            }
            _ => {
                return Err(Error::Corruption(format!(
                    "Unrecognized log item type: {item_type}"
                )));
            }
        };
        Ok(LogItem {
            raft_group_id,
            content,
        })
    }

    fn approximate_size(&self) -> usize {
        match &self.content {
            LogItemContent::EntryIndexes(entry_indexes) => {
                8 /*r_id*/ + 1 /*type*/ + entry_indexes.approximate_size()
            }
            LogItemContent::Command(cmd) => 8 + 1 + cmd.approximate_size(),
            LogItemContent::Kv(kv) => 8 + 1 + kv.approximate_size(),
        }
    }
}

pub(crate) type LogItemDrain<'a> = std::vec::Drain<'a, LogItem>;

/// A lean batch of log item, without entry data.
// Format:
// { item count | [items] | crc32 }
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LogItemBatch {
    items: Vec<LogItem>,
    item_size: usize,
    entries_size: u32,
    checksum: u32,
}

impl Default for LogItemBatch {
    fn default() -> Self {
        Self::with_capacity(0)
    }
}

impl LogItemBatch {
    pub fn with_capacity(cap: usize) -> Self {
        Self {
            items: Vec::with_capacity(cap),
            item_size: 0,
            entries_size: 0,
            checksum: 0,
        }
    }

    // TODO: Clean up these interfaces.
    pub fn into_items(self) -> Vec<LogItem> {
        self.items
    }

    pub fn iter(&self) -> std::slice::Iter<LogItem> {
        self.items.iter()
    }

    pub fn drain(&mut self) -> LogItemDrain {
        self.item_size = 0;
        self.entries_size = 0;
        self.checksum = 0;
        self.items.drain(..)
    }

    pub fn merge(&mut self, rhs: &mut LogItemBatch) {
        for item in &mut rhs.items {
            if let LogItemContent::EntryIndexes(entry_indexes) = &mut item.content {
                for ei in entry_indexes.0.iter_mut() {
                    ei.entry_offset += self.entries_size;
                }
            }
        }
        self.item_size += rhs.item_size;
        rhs.item_size = 0;
        self.entries_size += rhs.entries_size;
        rhs.entries_size = 0;
        self.items.append(&mut rhs.items);
    }

    pub(crate) fn finish_populate(&mut self, compression_type: CompressionType) {
        for item in self.items.iter_mut() {
            if let LogItemContent::EntryIndexes(entry_indexes) = &mut item.content {
                for ei in entry_indexes.0.iter_mut() {
                    ei.compression_type = compression_type;
                }
            }
        }
    }

    /// Prepare the `write` by signing a checksum, so-called `signature`,
    /// into the encoded buffer corresponding to `LogBatch`.
    ///
    /// The `signature` is both generated by the given `LogFileContext`.
    /// That is, the final checksum of each `LogBatch` consists of this
    /// `signature` and the original `checksum` of the contents.
    pub(crate) fn prepare_write(
        &self,
        buf: &mut [u8],
        file_context: &LogFileContext,
    ) -> Result<()> {
        if !buf.is_empty() {
            let mut footer_checksum = self.checksum;
            // Fill the placeholder (checksum) in `LogItemBatch` by inserting the
            // signature into the encoded bytes.
            let footer_checksum_offset = buf.len() - LOG_BATCH_CHECKSUM_LEN;
            if let Some(signature) = file_context.get_signature() {
                // The final checksum is generated by `signature` ***XOR***
                // `original checksum of buf`.
                footer_checksum ^= signature;
            }
            (&mut buf[footer_checksum_offset..]).write_u32::<LittleEndian>(footer_checksum)?;
        }
        Ok(())
    }

    pub(crate) fn finish_write(&mut self, handle: FileBlockHandle) {
        for item in self.items.iter_mut() {
            match &mut item.content {
                LogItemContent::EntryIndexes(entry_indexes) => {
                    for ei in entry_indexes.0.iter_mut() {
                        // No assert!(ei.entries.is_none):
                        // It's possible that batch containing rewritten index already
                        // has entries location.
                        ei.entries = Some(handle);
                    }
                }
                LogItemContent::Kv(kv) => {
                    debug_assert!(kv.file_id.is_none());
                    kv.file_id = Some(handle.id);
                }
                _ => {}
            }
        }
    }

    pub fn add_entry_indexes(&mut self, region_id: u64, mut entry_indexes: Vec<EntryIndex>) {
        for ei in entry_indexes.iter_mut() {
            ei.entry_offset = self.entries_size;
            self.entries_size += ei.entry_len;
        }
        let item = LogItem::new_entry_indexes(region_id, entry_indexes);
        self.item_size += item.approximate_size();
        self.items.push(item);
    }

    pub fn add_command(&mut self, region_id: u64, cmd: Command) {
        let item = LogItem::new_command(region_id, cmd);
        self.item_size += item.approximate_size();
        self.items.push(item);
    }

    pub fn delete(&mut self, region_id: u64, key: Vec<u8>) {
        let item = LogItem::new_kv(region_id, OpType::Del, key, None);
        self.item_size += item.approximate_size();
        self.items.push(item);
    }

    pub fn put_message<S: Message>(&mut self, region_id: u64, key: Vec<u8>, s: &S) -> Result<()> {
        self.put(region_id, key, s.write_to_bytes()?);
        Ok(())
    }

    pub fn put(&mut self, region_id: u64, key: Vec<u8>, value: Vec<u8>) {
        let item = LogItem::new_kv(region_id, OpType::Put, key, Some(value));
        self.item_size += item.approximate_size();
        self.items.push(item);
    }

    pub fn encode(&mut self, buf: &mut Vec<u8>) -> Result<()> {
        let offset = buf.len();
        let count = self.items.len() as u64;
        buf.encode_var_u64(count)?;
        for item in self.items.iter() {
            item.encode(buf)?;
        }
        self.checksum = crc32(&buf[offset..]);
        // Just leave a placeholder for the final checksum, which will be filled
        // by later `prepare_write(...)` progress.
        buf.encode_u32_le(0)?;
        Ok(())
    }

    /// Decodes a `LogItemBatch` from bytes of footer. `entries` is the block
    /// location of encoded entries.
    pub fn decode(
        buf: &mut SliceReader,
        entries: FileBlockHandle,
        compression_type: CompressionType,
        file_context: &LogFileContext,
    ) -> Result<LogItemBatch> {
        // Validate the checksum of each LogItemBatch by the signature.
        let checksum = verify_checksum_with_signature(buf, file_context.get_signature())?;
        *buf = &buf[..buf.len() - LOG_BATCH_CHECKSUM_LEN];
        let count = codec::decode_var_u64(buf)?;
        let mut items = LogItemBatch::with_capacity(count as usize);
        let mut entries_size = 0;
        for _ in 0..count {
            let item = LogItem::decode(buf, &mut entries_size)?;
            items.item_size += item.approximate_size();
            items.items.push(item);
        }
        items.entries_size = entries_size;

        for item in items.items.iter_mut() {
            if let LogItemContent::EntryIndexes(entry_indexes) = &mut item.content {
                for ei in entry_indexes.0.iter_mut() {
                    ei.compression_type = compression_type;
                    ei.entries = Some(entries);
                }
            } else if let LogItemContent::Kv(kv) = &mut item.content {
                kv.file_id = Some(entries.id);
            }
        }
        items.checksum = checksum;
        Ok(items)
    }

    pub fn approximate_size(&self) -> usize {
        8 /*count*/ + self.item_size + LOG_BATCH_CHECKSUM_LEN
    }

    /// Returns the first [`EntryIndex`] appeared in this batch.
    pub fn entry_index(&self) -> Option<EntryIndex> {
        for item in &self.items {
            if let LogItemContent::EntryIndexes(entry_indexes) = &item.content {
                return entry_indexes.0.first().cloned();
            }
        }
        None
    }
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
enum BufState {
    /// Buffer contains header and optionally entries.
    /// # Invariants
    /// LOG_BATCH_HEADER_LEN <= buf.len()
    Open,
    /// Buffer contains header, entries and footer; ready to be written. The
    /// footer may be signed with extra information depending on the format
    /// version.
    /// # Content
    /// (header_offset, entries_len)
    Encoded(usize, usize),
    /// Buffer contains header, entries and footer; ready to be written. This
    /// state only briefly exists between encoding and writing, user operation
    /// will panic under this state.
    /// # Content
    /// (header_offset, entries_len)
    /// # Invariants
    /// LOG_BATCH_HEADER_LEN <= buf.len()
    Sealed(usize, usize),
    /// Buffer is undergoing writes. User operation will panic under this state.
    Incomplete,
}

/// A batch of log items.
///
/// Encoding format:
/// - header = { u56 len | u8 compression type | u64 item offset }
/// - entries = { [entry..] (optionally compressed) | crc32 }
/// - footer = { item batch }
///
/// Size restriction:
/// - The total size of log entries must not exceed 2GiB.
///
/// Error will be raised if a to-be-added log item cannot fit within those
/// limits.
// Calling order:
// 1. Insert some log items
// 2. [`finish_populate`]
// 3. Write to disk with [`encoded_bytes`]
// 4. Update disk location with [`finish_write`]
// 5. Clean up the memory states with [`drain`]. Step 4 can be skipped if the states are not used
// (e.g. to apply memtable).
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct LogBatch {
    item_batch: LogItemBatch,
    buf_state: BufState,
    buf: Vec<u8>,
}

impl Default for LogBatch {
    fn default() -> Self {
        Self::with_capacity(DEFAULT_LOG_ITEM_BATCH_CAP)
    }
}

impl LogBatch {
    /// Creates a new, empty log batch capable of holding at least `cap` log
    /// items.
    pub fn with_capacity(cap: usize) -> Self {
        let mut buf = Vec::with_capacity(4096);
        buf.resize(LOG_BATCH_HEADER_LEN, 0);
        Self {
            item_batch: LogItemBatch::with_capacity(cap),
            buf_state: BufState::Open,
            buf,
        }
    }

    /// Moves all log items of `rhs` into `Self`, leaving `rhs` empty.
    pub fn merge(&mut self, rhs: &mut Self) -> Result<()> {
        debug_assert!(self.buf_state == BufState::Open && rhs.buf_state == BufState::Open);
        let max_entries_size = (|| {
            fail::fail_point!("log_batch::1kb_entries_size_per_batch", |_| 1024);
            MAX_LOG_ENTRIES_SIZE_PER_BATCH
        })();
        if !rhs.buf.is_empty() {
            if rhs.buf.len() + self.buf.len() > max_entries_size + LOG_BATCH_HEADER_LEN * 2 {
                return Err(Error::Full);
            }
            self.buf_state = BufState::Incomplete;
            rhs.buf_state = BufState::Incomplete;
            self.buf.extend_from_slice(&rhs.buf[LOG_BATCH_HEADER_LEN..]);
            rhs.buf.shrink_to(MAX_LOG_BATCH_BUFFER_CAP);
            rhs.buf.truncate(LOG_BATCH_HEADER_LEN);
        }
        self.item_batch.merge(&mut rhs.item_batch);
        self.buf_state = BufState::Open;
        rhs.buf_state = BufState::Open;
        Ok(())
    }

    /// Adds some protobuf log entries into the log batch.
    pub fn add_entries<M: MessageExt>(
        &mut self,
        region_id: u64,
        entries: &[M::Entry],
    ) -> Result<()> {
        debug_assert!(self.buf_state == BufState::Open);
        if entries.is_empty() {
            return Ok(());
        }

        let mut entry_indexes = Vec::with_capacity(entries.len());
        self.buf_state = BufState::Incomplete;
        let old_buf_len = self.buf.len();
        let max_entries_size = (|| {
            fail::fail_point!("log_batch::1kb_entries_size_per_batch", |_| 1024);
            MAX_LOG_ENTRIES_SIZE_PER_BATCH
        })();
        for e in entries {
            let buf_offset = self.buf.len();
            e.write_to_vec(&mut self.buf)?;
            if self.buf.len() > max_entries_size + LOG_BATCH_HEADER_LEN {
                self.buf.truncate(old_buf_len);
                self.buf_state = BufState::Open;
                return Err(Error::Full);
            }
            entry_indexes.push(EntryIndex {
                index: M::index(e),
                entry_len: (self.buf.len() - buf_offset) as u32,
                ..Default::default()
            });
        }
        self.item_batch.add_entry_indexes(region_id, entry_indexes);
        self.buf_state = BufState::Open;
        Ok(())
    }

    /// Adds some log entries with specified encoded data into the log batch.
    /// Assumes there are the same amount of entry indexes as the encoded data
    /// vectors.
    pub(crate) fn add_raw_entries(
        &mut self,
        region_id: u64,
        mut entry_indexes: Vec<EntryIndex>,
        entries: Vec<Vec<u8>>,
    ) -> Result<()> {
        debug_assert!(entry_indexes.len() == entries.len());
        debug_assert!(self.buf_state == BufState::Open);
        if entry_indexes.is_empty() {
            return Ok(());
        }

        self.buf_state = BufState::Incomplete;
        let old_buf_len = self.buf.len();
        let max_entries_size = (|| {
            fail::fail_point!("log_batch::1kb_entries_size_per_batch", |_| 1024);
            MAX_LOG_ENTRIES_SIZE_PER_BATCH
        })();
        for (ei, e) in entry_indexes.iter_mut().zip(entries.iter()) {
            if e.len() + self.buf.len() > max_entries_size + LOG_BATCH_HEADER_LEN {
                self.buf.truncate(old_buf_len);
                self.buf_state = BufState::Open;
                return Err(Error::Full);
            }
            let buf_offset = self.buf.len();
            self.buf.extend(e);
            ei.entry_len = (self.buf.len() - buf_offset) as u32;
        }
        self.item_batch.add_entry_indexes(region_id, entry_indexes);
        self.buf_state = BufState::Open;
        Ok(())
    }

    /// Adds a command into the log batch.
    pub fn add_command(&mut self, region_id: u64, cmd: Command) {
        self.item_batch.add_command(region_id, cmd);
    }

    /// Removes a key value pair from the log batch.
    pub fn delete(&mut self, region_id: u64, key: Vec<u8>) {
        self.item_batch.delete(region_id, key);
    }

    /// Adds a protobuf key value pair into the log batch.
    pub fn put_message<S: Message>(&mut self, region_id: u64, key: Vec<u8>, s: &S) -> Result<()> {
        if crate::is_internal_key(&key, None) {
            return Err(Error::InvalidArgument(format!(
                "key prefix `{:?}` reserved for internal use",
                crate::INTERNAL_KEY_PREFIX
            )));
        }
        self.item_batch.put_message(region_id, key, s)
    }

    /// Adds a key value pair into the log batch.
    pub fn put(&mut self, region_id: u64, key: Vec<u8>, value: Vec<u8>) -> Result<()> {
        if crate::is_internal_key(&key, None) {
            return Err(Error::InvalidArgument(format!(
                "key prefix `{:?}` reserved for internal use",
                crate::INTERNAL_KEY_PREFIX
            )));
        }
        self.item_batch.put(region_id, key, value);
        Ok(())
    }

    pub(crate) fn put_unchecked(&mut self, region_id: u64, key: Vec<u8>, value: Vec<u8>) {
        self.item_batch.put(region_id, key, value);
    }

    /// Returns true if the log batch contains no log item.
    pub fn is_empty(&self) -> bool {
        self.item_batch.items.is_empty()
    }

    /// Notifies the completion of log item population. User must not add any
    /// more log content after this call. Returns the length of encoded data.
    ///
    /// Internally, encodes and optionally compresses log entries. Sets the
    /// compression type to each entry index.
    pub(crate) fn finish_populate(
        &mut self,
        compression_threshold: usize,
        compression_level: Option<usize>,
    ) -> Result<usize> {
        let _t = StopWatch::new(perf_context!(log_populating_duration));
        debug_assert!(self.buf_state == BufState::Open);
        if self.is_empty() {
            self.buf_state = BufState::Encoded(self.buf.len(), 0);
            return Ok(0);
        }
        self.buf_state = BufState::Incomplete;

        // entries
        let (header_offset, compression_type) = if compression_threshold > 0
            && self.buf.len() >= LOG_BATCH_HEADER_LEN + compression_threshold
        {
            let buf_len = self.buf.len();
            lz4::append_compress_block(
                &mut self.buf,
                LOG_BATCH_HEADER_LEN,
                compression_level.unwrap_or(lz4::DEFAULT_LZ4_COMPRESSION_LEVEL),
            )?;
            (buf_len - LOG_BATCH_HEADER_LEN, CompressionType::Lz4)
        } else {
            (0, CompressionType::None)
        };

        // checksum
        if self.buf.len() > header_offset + LOG_BATCH_HEADER_LEN {
            let checksum = crc32(&self.buf[header_offset + LOG_BATCH_HEADER_LEN..]);
            self.buf.encode_u32_le(checksum)?;
        }
        // `footer_roffset` records the start offset of encoded `self.item_batch`
        let footer_roffset = self.buf.len() - header_offset;

        // footer
        self.item_batch.encode(&mut self.buf)?;
        self.item_batch.finish_populate(compression_type);

        // header
        let len =
            (((self.buf.len() - header_offset) as u64) << 8) | u64::from(compression_type.to_u8());
        (&mut self.buf[header_offset..header_offset + 8]).write_u64::<BigEndian>(len)?;
        (&mut self.buf[header_offset + 8..header_offset + 16])
            .write_u64::<BigEndian>(footer_roffset as u64)?;

        #[cfg(feature = "failpoints")]
        {
            let corrupted_items = || {
                fail::fail_point!("log_batch::corrupted_items", |_| true);
                false
            };
            if corrupted_items() {
                self.buf[footer_roffset] += 1;
            }
            let corrupted_entries = || {
                fail::fail_point!("log_batch::corrupted_entries", |_| true);
                false
            };
            if corrupted_entries() {
                assert!(footer_roffset > LOG_BATCH_HEADER_LEN);
                self.buf[footer_roffset - 1] += 1;
            }
        }

        self.buf_state = BufState::Encoded(header_offset, footer_roffset - LOG_BATCH_HEADER_LEN);
        Ok(self.buf.len() - header_offset)
    }

    /// Make preparations for the write of `LogBatch`.
    #[inline]
    pub(crate) fn prepare_write(&mut self, file_context: &LogFileContext) -> Result<()> {
        match self.buf_state {
            // `BufState::Sealed` means that `LogBatch` is under a repeated state of dumping.
            BufState::Encoded(header_offset, entries_len)
            | BufState::Sealed(header_offset, entries_len) => {
                self.item_batch
                    .prepare_write(&mut self.buf[header_offset + entries_len..], file_context)?;
                self.buf_state = BufState::Sealed(header_offset, entries_len);
            }
            _ => unreachable!(),
        }
        Ok(())
    }

    /// Returns a slice of bytes containing encoded data of this log batch.
    /// Assumes called after a successful call of [`prepare_write`].
    pub(crate) fn encoded_bytes(&self) -> &[u8] {
        match self.buf_state {
            BufState::Sealed(header_offset, _) => &self.buf[header_offset..],
            _ => unreachable!(),
        }
    }

    /// Notifies the completion of a storage write with the written location.
    ///
    /// Internally sets the file locations of each log entry indexes.
    pub(crate) fn finish_write(&mut self, mut handle: FileBlockHandle) {
        debug_assert!(matches!(self.buf_state, BufState::Sealed(_, _)));
        if !self.is_empty() {
            // adjust log batch handle to log entries handle.
            handle.offset += LOG_BATCH_HEADER_LEN as u64;
            match self.buf_state {
                BufState::Sealed(_, entries_len) => {
                    debug_assert!(LOG_BATCH_HEADER_LEN + entries_len < handle.len);
                    handle.len = entries_len;
                }
                _ => unreachable!(),
            }
        }
        self.item_batch.finish_write(handle);
    }

    /// Consumes log items into an iterator.
    pub(crate) fn drain(&mut self) -> LogItemDrain {
        debug_assert!(!matches!(self.buf_state, BufState::Incomplete));

        self.buf.shrink_to(MAX_LOG_BATCH_BUFFER_CAP);
        self.buf.truncate(LOG_BATCH_HEADER_LEN);
        self.buf_state = BufState::Open;
        self.item_batch.drain()
    }

    /// Returns approximate encoded size of this log batch. Might be larger
    /// than the actual size.
    pub fn approximate_size(&self) -> usize {
        if self.is_empty() {
            0
        } else {
            match self.buf_state {
                BufState::Open => {
                    self.buf.len() + LOG_BATCH_CHECKSUM_LEN + self.item_batch.approximate_size()
                }
                BufState::Encoded(header_offset, _) => self.buf.len() - header_offset,
                BufState::Sealed(header_offset, _) => self.buf.len() - header_offset,
                s => {
                    error!("querying incomplete log batch with state {s:?}");
                    0
                }
            }
        }
    }

    /// Returns header information from some bytes.
    ///
    /// The information includes:
    ///
    /// + The offset of log items
    /// + The compression type of entries
    /// + The total length of this log batch.
    pub(crate) fn decode_header(buf: &mut SliceReader) -> Result<(usize, CompressionType, usize)> {
        if buf.len() < LOG_BATCH_HEADER_LEN {
            return Err(Error::Corruption(format!(
                "Log batch header too short: {}",
                buf.len()
            )));
        }

        let len_and_type = codec::decode_u64(buf)? as usize;
        let compression_type = CompressionType::from_u8(len_and_type as u8)?;
        let len = len_and_type >> 8;
        let offset = codec::decode_u64(buf)? as usize;
        if offset > len {
            return Err(Error::Corruption(
                "Log item offset exceeds log batch length".to_owned(),
            ));
        } else if offset < LOG_BATCH_HEADER_LEN {
            return Err(Error::Corruption(
                "Log item offset is smaller than log batch header length".to_owned(),
            ));
        }
        Ok((offset, compression_type, len))
    }

    /// Unfolds bytes of multiple user entries from an encoded block.
    pub(crate) fn decode_entries_block(
        buf: &[u8],
        handle: FileBlockHandle,
        compression: CompressionType,
    ) -> Result<Vec<u8>> {
        if handle.len > 0 {
            let _ = verify_checksum_with_signature(&buf[0..handle.len], None)?;
            match compression {
                CompressionType::None => Ok(buf[..handle.len - LOG_BATCH_CHECKSUM_LEN].to_owned()),
                CompressionType::Lz4 => {
                    let decompressed =
                        lz4::decompress_block(&buf[..handle.len - LOG_BATCH_CHECKSUM_LEN])?;
                    Ok(decompressed)
                }
            }
        } else {
            Ok(Vec::new())
        }
    }
}

impl ReactiveBytes for LogBatch {
    fn as_bytes(&mut self, ctx: &LogFileContext) -> &[u8] {
        self.prepare_write(ctx).unwrap();
        self.encoded_bytes()
    }
}

/// Verifies the checksum of a slice of bytes that sequentially holds data and
/// checksum. The checksum field may be signed by XOR-ing with an u32.
///
/// Returns the checksum of the buffer without signature.
fn verify_checksum_with_signature(buf: &[u8], signature: Option<u32>) -> Result<u32> {
    if buf.len() <= LOG_BATCH_CHECKSUM_LEN {
        return Err(Error::Corruption(format!(
            "Content too short {}",
            buf.len()
        )));
    }
    let actual = crc32(&buf[..buf.len() - LOG_BATCH_CHECKSUM_LEN]);
    let mut expected = codec::decode_u32_le(&mut &buf[buf.len() - LOG_BATCH_CHECKSUM_LEN..])?;
    if let Some(signature) = signature {
        expected ^= signature;
    }
    if actual != expected {
        return Err(Error::Corruption(format!(
            "Checksum expected {expected} but got {actual}"
        )));
    }
    Ok(actual)
}

lazy_static! {
    static ref ATOMIC_GROUP_ID: Arc<AtomicU64> = Arc::new(AtomicU64::new(0));
}
pub(crate) const ATOMIC_GROUP_KEY: &[u8] = &[0x01];
// <status>
const ATOMIC_GROUP_VALUE_LEN: usize = 1;

#[repr(u8)]
#[derive(Clone, Copy, FromPrimitive, Debug, PartialEq)]
pub(crate) enum AtomicGroupStatus {
    Begin = 0,
    Middle = 1,
    End = 2,
}

impl AtomicGroupStatus {
    /// Whether the log batch with `item` belongs to an atomic group.
    pub fn parse(item: &LogItem) -> Option<(u64, AtomicGroupStatus)> {
        if let LogItemContent::Kv(KeyValue {
            op_type,
            key,
            value,
            ..
        }) = &item.content
        {
            if *op_type == OpType::Put
                && crate::is_internal_key(key, Some(ATOMIC_GROUP_KEY))
                && value.as_ref().unwrap().len() == ATOMIC_GROUP_VALUE_LEN
            {
                let value = &mut value.as_ref().unwrap().as_slice();
                return Some((
                    item.raft_group_id,
                    AtomicGroupStatus::from_u8(value[0]).unwrap(),
                ));
            }
        }
        None
    }
}

/// Group multiple log batches as an atomic operation.
///
/// Caveats:
/// (1) The atomicity is provided at persistent level. This means, once an
/// atomic group fails, the in-memory value will be inconsistent with what can
/// be recovered from on-disk data files.
/// (2) The recovery replay order will be different from original write order.
/// Log batches in a completed atomic group will be replayed as if they were
/// written together at an arbitary time point within the group.
/// (3) Atomic group is implemented by embedding normal key-values into user
/// writes. These keys have internal key prefix and will not be replayed into
/// memtable. However, when read by an older version, they will behave as user
/// keys. They may also belong to Raft Group that doesn't exist before.
///
/// In practice, we only use atomic group for rewrite operation. (In fact,
/// atomic group markers in append queue are simply ignored.) Rewrite doesn't
/// change the value of entries, just locations. So first issue doesn't affect
/// correctness. There could only be one worker doing the rewrite. So second
/// issue doesn't change observed write order because there's no mixed write.
pub(crate) struct AtomicGroupBuilder {
    id: u64,
    status: Option<AtomicGroupStatus>,
}

impl Default for AtomicGroupBuilder {
    fn default() -> Self {
        Self {
            // We only care there's no collision between concurrent groups.
            id: ATOMIC_GROUP_ID.fetch_add(1, Ordering::Relaxed),
            status: None,
        }
    }
}

impl AtomicGroupBuilder {
    /// Each log batch can only carry one atomic group marker. If multiple are
    /// present only the first is recognized.
    pub fn begin(&mut self, lb: &mut LogBatch) {
        fail::fail_point!("atomic_group::begin");
        assert_eq!(self.status, None);
        self.status = Some(AtomicGroupStatus::Begin);
        self.flush(lb);
    }

    pub fn add(&mut self, lb: &mut LogBatch) {
        fail::fail_point!("atomic_group::add");
        assert!(matches!(
            self.status,
            Some(AtomicGroupStatus::Begin | AtomicGroupStatus::Middle)
        ));
        self.status = Some(AtomicGroupStatus::Middle);
        self.flush(lb);
    }

    pub fn end(&mut self, lb: &mut LogBatch) {
        assert!(matches!(
            self.status,
            Some(AtomicGroupStatus::Begin | AtomicGroupStatus::Middle)
        ));
        self.status = Some(AtomicGroupStatus::End);
        self.flush(lb);
    }

    #[inline]
    fn flush(&self, lb: &mut LogBatch) {
        let mut s = Vec::with_capacity(ATOMIC_GROUP_VALUE_LEN);
        s.push(self.status.unwrap() as u8);
        lb.put_unchecked(self.id, crate::make_internal_key(ATOMIC_GROUP_KEY), s);
    }

    #[cfg(test)]
    pub fn with_id(id: u64) -> Self {
        Self { id, status: None }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pipe_log::{LogQueue, Version};
    use crate::test_util::{catch_unwind_silent, generate_entries, generate_entry_indexes_opt};
    use protobuf::parse_from_bytes;
    use raft::eraftpb::Entry;
    use strum::IntoEnumIterator;

    fn decode_entries_from_bytes<M: MessageExt>(
        buf: &[u8],
        entry_indexes: &[EntryIndex],
        _encoded: bool,
    ) -> Vec<M::Entry> {
        let mut entries = Vec::with_capacity(entry_indexes.len());
        for ei in entry_indexes {
            let block =
                LogBatch::decode_entries_block(buf, ei.entries.unwrap(), ei.compression_type)
                    .unwrap();
            entries.push(
                parse_from_bytes(
                    &block[ei.entry_offset as usize..(ei.entry_offset + ei.entry_len) as usize],
                )
                .unwrap(),
            );
        }
        entries
    }

    #[test]
    fn test_entry_indexes_enc_dec() {
        fn encode_and_decode(entry_indexes: &mut [EntryIndex]) -> EntryIndexes {
            let mut entries_size = 0;
            for idx in entry_indexes.iter_mut() {
                idx.entry_offset = entries_size;
                entries_size += idx.entry_len;
            }
            let entry_indexes = EntryIndexes(entry_indexes.to_vec());

            let mut encoded = vec![];
            entry_indexes.encode(&mut encoded).unwrap();
            let mut bytes_slice = encoded.as_slice();
            let mut decoded_entries_size = 0;
            let decoded_indexes =
                EntryIndexes::decode(&mut bytes_slice, &mut decoded_entries_size).unwrap();
            assert_eq!(bytes_slice.len(), 0);
            assert!(decoded_indexes.approximate_size() >= encoded.len());
            assert_eq!(decoded_entries_size, entries_size);
            decoded_indexes
        }

        let entry_indexes = vec![Vec::new(), generate_entry_indexes_opt(7, 17, None)];
        for mut idxs in entry_indexes.into_iter() {
            let decoded = encode_and_decode(&mut idxs);
            assert_eq!(idxs, decoded.0);
        }

        let mut entry_indexes_with_file_id =
            generate_entry_indexes_opt(7, 17, Some(FileId::new(LogQueue::Append, 7)));
        let mut decoded = encode_and_decode(&mut entry_indexes_with_file_id);
        assert_ne!(entry_indexes_with_file_id, decoded.0);
        for i in decoded.0.iter_mut() {
            i.entries = None;
        }
        assert_ne!(entry_indexes_with_file_id, decoded.0);
    }

    #[test]
    fn test_command_enc_dec() {
        let cmds = vec![Command::Clean, Command::Compact { index: 7 }];
        let invalid_command_type = 7;
        for cmd in cmds.into_iter() {
            let mut encoded = vec![];
            cmd.encode(&mut encoded);
            let mut bytes_slice = encoded.as_slice();
            let decoded_cmd = Command::decode(&mut bytes_slice).unwrap();
            assert_eq!(bytes_slice.len(), 0);
            assert!(decoded_cmd.approximate_size() >= encoded.len());
            assert_eq!(cmd, decoded_cmd);

            encoded[0] = invalid_command_type;
            let expected = format!("Unrecognized command type: {invalid_command_type}");
            assert!(matches!(
                Command::decode(&mut encoded.as_slice()),
                Err(Error::Corruption(m)) if m == expected
            ));
        }
    }

    #[test]
    fn test_kv_enc_dec() {
        let kvs = vec![
            KeyValue::new(OpType::Put, b"put".to_vec(), Some(b"put_v".to_vec())),
            KeyValue::new(OpType::Del, b"del".to_vec(), None),
        ];
        let invalid_op_type = 7;
        for kv in kvs.into_iter() {
            let mut encoded = vec![];
            kv.encode(&mut encoded).unwrap();
            let mut bytes_slice = encoded.as_slice();
            let decoded_kv = KeyValue::decode(&mut bytes_slice).unwrap();
            assert_eq!(bytes_slice.len(), 0);
            assert!(decoded_kv.approximate_size() >= encoded.len());
            assert_eq!(kv, decoded_kv);

            encoded[0] = invalid_op_type;
            let expected = format!("Unrecognized op type: {invalid_op_type}");
            assert!(matches!(
                KeyValue::decode(&mut encoded.as_slice()),
                Err(Error::Corruption(m)) if m == expected
            ));
        }

        let del_with_value = KeyValue::new(OpType::Del, b"del".to_vec(), Some(b"del_v".to_vec()));
        let mut encoded = vec![];
        del_with_value.encode(&mut encoded).unwrap();
        let mut bytes_slice = encoded.as_slice();
        let decoded_kv = KeyValue::decode(&mut bytes_slice).unwrap();
        assert_eq!(bytes_slice.len(), 0);
        assert!(decoded_kv.value.is_none());
    }

    #[test]
    fn test_log_item_enc_dec() {
        let items = vec![
            LogItem::new_entry_indexes(7, generate_entry_indexes_opt(7, 17, None)),
            LogItem::new_command(17, Command::Compact { index: 7 }),
            LogItem::new_kv(27, OpType::Put, b"key".to_vec(), Some(b"value".to_vec())),
        ];
        let invalid_log_item_type = 7;
        for mut item in items.into_iter() {
            let mut entries_size = 0;
            if let LogItemContent::EntryIndexes(EntryIndexes(indexes)) = &mut item.content {
                for index in indexes.iter_mut() {
                    index.entry_offset = entries_size;
                    entries_size += index.entry_len;
                }
            }
            let mut encoded = vec![];
            item.encode(&mut encoded).unwrap();
            let mut bytes_slice = encoded.as_slice();
            let mut decoded_entries_size = 0;
            let decoded_item =
                LogItem::decode(&mut bytes_slice, &mut decoded_entries_size).unwrap();
            assert_eq!(bytes_slice.len(), 0);
            assert_eq!(decoded_entries_size, entries_size);
            assert!(decoded_item.approximate_size() >= encoded.len());
            assert_eq!(item, decoded_item);

            // consume raft group id.
            bytes_slice = encoded.as_slice();
            codec::decode_var_u64(&mut bytes_slice).unwrap();
            let next_u8 = encoded.len() - bytes_slice.len();
            encoded[next_u8] = invalid_log_item_type;
            let expected = format!("Unrecognized log item type: {invalid_log_item_type}");
            assert!(matches!(
                LogItem::decode(&mut encoded.as_slice(), &mut decoded_entries_size),
                Err(Error::Corruption(m)) if m == expected
            ));
        }
    }

    #[test]
    fn test_log_item_batch_enc_dec() {
        let mut batches = vec![LogItemBatch::default()];
        let mut batch = LogItemBatch::default();
        batch.add_entry_indexes(7, generate_entry_indexes_opt(1, 5, None /* file_id */));
        batch.add_entry_indexes(
            7 + 100,
            generate_entry_indexes_opt(100, 105, None /* file_id */),
        );
        batch.add_command(7, Command::Clean);
        batch.put(7, b"key".to_vec(), b"value".to_vec());
        batch.delete(7, b"key2".to_vec());
        batches.push(batch);

        for batch in batches.into_iter() {
            for compression_type in [CompressionType::Lz4, CompressionType::None] {
                let mut batch = batch.clone();
                batch.finish_populate(compression_type);
                let mut encoded_batch = vec![];
                batch.encode(&mut encoded_batch).unwrap();
                let file_context =
                    LogFileContext::new(FileId::dummy(LogQueue::Append), Version::default());
                batch
                    .prepare_write(&mut encoded_batch, &file_context)
                    .unwrap();
                batch.finish_write(FileBlockHandle::dummy(LogQueue::Append));
                let decoded_batch = LogItemBatch::decode(
                    &mut encoded_batch.as_slice(),
                    FileBlockHandle::dummy(LogQueue::Append),
                    compression_type,
                    &file_context,
                )
                .unwrap();
                assert!(decoded_batch.approximate_size() >= encoded_batch.len());
                assert_eq!(batch, decoded_batch);
            }
        }
    }

    #[test]
    fn test_log_batch_enc_dec() {
        fn decode_and_encode(
            mut batch: LogBatch,
            compress: bool,
            version: Version,
            entry_data: &[u8],
        ) {
            // Test call protocol violation.
            assert!(catch_unwind_silent(|| batch.encoded_bytes()).is_err());
            assert!(catch_unwind_silent(
                || batch.finish_write(FileBlockHandle::dummy(LogQueue::Append))
            )
            .is_err());
            let mocked_file_block_handle = FileBlockHandle {
                id: FileId::new(LogQueue::Append, 12),
                len: 0,
                offset: 0,
            };
            let old_approximate_size = batch.approximate_size();
            let len = batch.finish_populate(usize::from(compress), None).unwrap();
            assert!(old_approximate_size >= len);
            assert_eq!(batch.approximate_size(), len);
            let mut batch_handle = mocked_file_block_handle;
            batch_handle.len = len;
            let file_context = LogFileContext::new(batch_handle.id, version);
            batch.prepare_write(&file_context).unwrap();
            batch.finish_write(batch_handle);
            let encoded = batch.encoded_bytes();
            assert_eq!(encoded.len(), len);
            if len < LOG_BATCH_HEADER_LEN {
                assert_eq!(len, 0);
                let expected = "Log batch header too short: 0";
                assert!(matches!(
                    LogBatch::decode_header(&mut &*encoded),
                    Err(Error::Corruption(m)) if m == expected
                ));
                return;
            }

            let item_batch = batch.item_batch.clone();
            // decode item batch
            let mut bytes_slice = encoded;
            let (offset, compression_type, len) =
                LogBatch::decode_header(&mut bytes_slice).unwrap();
            assert_eq!(len, encoded.len());
            assert_eq!(bytes_slice.len() + LOG_BATCH_HEADER_LEN, encoded.len());
            let mut entries_handle = mocked_file_block_handle;
            entries_handle.offset = LOG_BATCH_HEADER_LEN as u64;
            entries_handle.len = offset - LOG_BATCH_HEADER_LEN;
            let file_context = LogFileContext::new(entries_handle.id, version);
            {
                // Decoding with wrong compression type is okay.
                LogItemBatch::decode(
                    &mut &encoded[offset..],
                    entries_handle,
                    if compression_type == CompressionType::None {
                        CompressionType::Lz4
                    } else {
                        CompressionType::None
                    },
                    &file_context,
                )
                .unwrap();
                // Decode with wrong file number.
                if version.has_log_signing() {
                    LogItemBatch::decode(
                        &mut &encoded[offset..],
                        entries_handle,
                        compression_type,
                        &LogFileContext::new(FileId::new(LogQueue::Append, u64::MAX), version),
                    )
                    .unwrap_err();
                }
                // Decode with wrong version.
                LogItemBatch::decode(
                    &mut &encoded[offset..],
                    entries_handle,
                    compression_type,
                    &LogFileContext::new(
                        file_context.id,
                        if version == Version::V1 {
                            Version::V2
                        } else {
                            Version::V1
                        },
                    ),
                )
                .unwrap_err();
            }
            let decoded_item_batch = LogItemBatch::decode(
                &mut &encoded[offset..],
                entries_handle,
                compression_type,
                &file_context,
            )
            .unwrap();
            assert_eq!(decoded_item_batch, item_batch);
            assert!(decoded_item_batch.approximate_size() >= len - offset);

            let entries = &encoded[LOG_BATCH_HEADER_LEN..offset];
            for item in decoded_item_batch.items.iter() {
                if let LogItemContent::EntryIndexes(entry_indexes) = &item.content {
                    if !entry_indexes.0.is_empty() {
                        let (begin, end) = (
                            entry_indexes.0.first().unwrap().index,
                            entry_indexes.0.last().unwrap().index + 1,
                        );
                        let origin_entries = generate_entries(begin, end, Some(entry_data));
                        let decoded_entries =
                            decode_entries_from_bytes::<Entry>(entries, &entry_indexes.0, false);
                        assert_eq!(origin_entries, decoded_entries);
                    }
                }
            }
        }

        let mut batches = vec![(LogBatch::default(), Vec::new())];
        let mut batch = LogBatch::default();
        let entry_data = vec![b'x'; 1024];
        batch
            .add_entries::<Entry>(7, &generate_entries(1, 11, Some(&entry_data)))
            .unwrap();
        batch.add_command(7, Command::Clean);
        batch.put(7, b"key".to_vec(), b"value".to_vec()).unwrap();
        batch.delete(7, b"key2".to_vec());
        batch
            .add_entries::<Entry>(7, &generate_entries(1, 11, Some(&entry_data)))
            .unwrap();
        batches.push((batch, entry_data));
        let mut batch = LogBatch::default();
        batch
            .add_entries::<Entry>(17, &generate_entries(0, 1, None))
            .unwrap();
        batch
            .add_entries::<Entry>(27, &generate_entries(1, 11, None))
            .unwrap();
        batches.push((batch, Vec::new()));

        // Validate with different Versions
        for version in Version::iter() {
            for compress in [true, false] {
                for (batch, entry_data) in batches.clone().into_iter() {
                    decode_and_encode(batch, compress, version, &entry_data);
                }
            }
        }
    }

    #[test]
    fn test_log_batch_merge() {
        let region_id = 8;
        let mut entries = Vec::new();
        let mut kvs = Vec::new();
        let data = vec![b'x'; 1024];
        let file_id = FileId::dummy(LogQueue::Append);
        let file_context = LogFileContext::new(file_id, Version::default());

        let mut batch1 = LogBatch::default();
        entries.push(generate_entries(1, 11, Some(&data)));
        batch1
            .add_entries::<Entry>(region_id, entries.last().unwrap())
            .unwrap();
        for i in 0..=2 {
            let (k, v) = (format!("k{i}").into_bytes(), format!("v{i}").into_bytes());
            batch1.put(region_id, k.clone(), v.clone()).unwrap();
            kvs.push((k, v));
        }

        batch1.merge(&mut LogBatch::default()).unwrap();

        let mut batch2 = LogBatch::default();
        entries.push(generate_entries(11, 21, Some(&data)));
        batch2
            .add_entries::<Entry>(region_id, entries.last().unwrap())
            .unwrap();
        for i in 3..=5 {
            let (k, v) = (format!("k{i}").into_bytes(), format!("v{i}").into_bytes());
            batch2.put(region_id, k.clone(), v.clone()).unwrap();
            kvs.push((k, v));
        }

        batch1.merge(&mut batch2).unwrap();
        assert!(batch2.is_empty());

        let len = batch1.finish_populate(0, None).unwrap();
        batch1.prepare_write(&file_context).unwrap();
        let encoded = batch1.encoded_bytes();
        assert_eq!(len, encoded.len());

        // decode item batch
        let (offset, compression_type, len) = LogBatch::decode_header(&mut &*encoded).unwrap();
        assert_eq!(encoded.len(), len);
        let decoded_item_batch = LogItemBatch::decode(
            &mut &encoded[offset..],
            FileBlockHandle {
                id: file_id,
                offset: 0,
                len: offset - LOG_BATCH_HEADER_LEN,
            },
            compression_type,
            &file_context,
        )
        .unwrap();

        // decode and assert entries
        let entry_bytes = &encoded[LOG_BATCH_HEADER_LEN..offset];
        for item in decoded_item_batch.items.iter() {
            match &item.content {
                LogItemContent::EntryIndexes(entry_indexes) => {
                    let decoded_entries =
                        decode_entries_from_bytes::<Entry>(entry_bytes, &entry_indexes.0, false);
                    assert_eq!(entries.remove(0), decoded_entries);
                }
                LogItemContent::Kv(kv) => {
                    let (k, v) = kvs.remove(0);
                    assert_eq!(OpType::Put, kv.op_type);
                    assert_eq!(k, kv.key);
                    assert_eq!(&v, kv.value.as_ref().unwrap());
                }
                _ => unreachable!(),
            }
        }
    }

    #[test]
    fn test_empty_log_batch() {
        let mut batch = LogBatch::default();
        assert!(batch.is_empty());
        batch.add_entries::<Entry>(0, &Vec::new()).unwrap();
        assert!(batch.is_empty());
        batch.add_raw_entries(0, Vec::new(), Vec::new()).unwrap();
        assert!(batch.is_empty());
        // Encoding empty LogBatch.
        {
            let mocked_file_block_handles = FileBlockHandle {
                id: FileId::new(LogQueue::Append, 12),
                len: 0,
                offset: 0,
            };
            let buf_len = batch.buf.len();
            let len = batch.finish_populate(1, None).unwrap();
            assert!(len == 0);
            assert_eq!(batch.buf_state, BufState::Encoded(buf_len, 0));
            let file_context = LogFileContext::new(mocked_file_block_handles.id, Version::V2);
            batch.prepare_write(&file_context).unwrap();
            assert!(batch.is_empty());
            assert_eq!(batch.buf_state, BufState::Sealed(buf_len, 0));
        }
    }

    #[test]
    fn test_internal_key() {
        let mut batch = LogBatch::default();
        assert!(matches!(
            batch
                .put(0, crate::make_internal_key(&[0]), b"v".to_vec())
                .unwrap_err(),
            Error::InvalidArgument(_)
        ));
        assert!(matches!(
            batch
                .put_message(0, crate::make_internal_key(ATOMIC_GROUP_KEY), &Entry::new())
                .unwrap_err(),
            Error::InvalidArgument(_)
        ));
    }

    #[test]
    fn test_header_corruption() {
        let region_id = 7;
        let data = vec![b'x'; 16];
        let mut batch = LogBatch::default();
        batch
            .add_entries::<Entry>(region_id, &generate_entries(1, 11, Some(&data)))
            .unwrap();
        batch
            .put(region_id, b"key".to_vec(), b"value".to_vec())
            .unwrap();
        // enable compression so that len_and_type > len.
        batch.finish_populate(1, None).unwrap();
        let file_context = LogFileContext::new(FileId::dummy(LogQueue::Append), Version::default());
        batch.prepare_write(&file_context).unwrap();
        let encoded = batch.encoded_bytes();

        let mut copy = encoded.to_owned();
        copy.truncate(LOG_BATCH_HEADER_LEN - 1);
        assert!(LogBatch::decode_header(&mut copy.as_slice())
            .unwrap_err()
            .to_string()
            .contains("Log batch header too short"));

        let mut copy = encoded.to_owned();
        (&mut copy[LOG_BATCH_HEADER_LEN - 8..LOG_BATCH_HEADER_LEN])
            .write_u64::<BigEndian>(encoded.len() as u64 + 1)
            .unwrap();
        assert!(LogBatch::decode_header(&mut copy.as_slice())
            .unwrap_err()
            .to_string()
            .contains("Log item offset exceeds log batch length"));

        let mut copy = encoded.to_owned();
        (&mut copy[LOG_BATCH_HEADER_LEN - 8..LOG_BATCH_HEADER_LEN])
            .write_u64::<BigEndian>(LOG_BATCH_HEADER_LEN as u64 - 1)
            .unwrap();
        assert!(LogBatch::decode_header(&mut copy.as_slice())
            .unwrap_err()
            .to_string()
            .contains("Log item offset is smaller than log batch header length"));
    }

    #[cfg(feature = "nightly")]
    #[bench]
    fn bench_log_batch_add_entry_and_encode(b: &mut test::Bencher) {
        use rand::{thread_rng, Rng};
        fn details(log_batch: &mut LogBatch, entries: &[Entry], regions: usize) {
            for _ in 0..regions {
                log_batch
                    .add_entries::<Entry>(thread_rng().gen(), entries)
                    .unwrap();
            }
            log_batch.finish_populate(0, None).unwrap();
            let _ = log_batch.drain();
        }
        let data: Vec<u8> = (0..128).map(|_| thread_rng().gen()).collect();
        let entries = generate_entries(1, 11, Some(&data));
        let mut log_batch = LogBatch::default();
        // warm up
        details(&mut log_batch, &entries, 100);
        b.iter(move || {
            details(&mut log_batch, &entries, 100);
        });
    }

    #[test]
    fn test_log_batch_sign_signature_repeatedly() {
        // Set a LogBatch and encode the LogBatch by `finish_populate`.
        let mut batch = LogBatch::default();
        batch
            .add_entries::<Entry>(17, &generate_entries(0, 1, None))
            .unwrap();
        batch
            .add_entries::<Entry>(27, &generate_entries(1, 11, None))
            .unwrap();

        let mocked_file_block_handles = [
            FileBlockHandle {
                id: FileId::new(LogQueue::Append, 12),
                len: 0,
                offset: 0,
            },
            FileBlockHandle {
                id: FileId::new(LogQueue::Append, 18),
                len: 0,
                offset: 0,
            },
            FileBlockHandle {
                id: FileId::new(LogQueue::Append, 2001),
                len: 0,
                offset: 0,
            },
        ];
        let old_approximate_size = batch.approximate_size();
        let len = batch.finish_populate(1, None).unwrap();
        assert!(old_approximate_size >= len);
        assert_eq!(batch.approximate_size(), len);
        let checksum = batch.item_batch.checksum;

        // Repeatedly sign signature to this batch, followed by decoding the signature
        // and verifying the checksum.
        for handle in mocked_file_block_handles {
            let mut batch_handle = handle;
            batch_handle.len = len;
            let file_context = LogFileContext::new(batch_handle.id, Version::V2);
            batch.prepare_write(&file_context).unwrap();
            assert_eq!(batch.approximate_size(), len);
            let encoded = batch.encoded_bytes();
            assert_eq!(encoded.len(), len);
            let mut bytes_slice = encoded;
            let (offset, _, _) = LogBatch::decode_header(&mut bytes_slice).unwrap();
            let expected =
                verify_checksum_with_signature(&encoded[offset..], file_context.get_signature())
                    .unwrap();
            assert_eq!(expected, checksum);
        }
    }
}
