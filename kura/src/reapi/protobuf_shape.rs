use tonic::Status;

pub(super) const BYTESTREAM_WRITE_DECODE_COPIES: u64 = 2;
pub(super) const CAS_BATCH_UPDATE_DECODE_COPIES: u64 = 3;
pub(super) const ACTION_CACHE_UPDATE_DECODE_COPIES: u64 = 4;
pub(super) const REAPI_BATCH_REQUEST_STRUCTURAL_BYTES: u64 = 512;
pub(super) const REAPI_ACTION_OUTPUT_STRUCTURAL_BYTES: u64 = 1_024;
const REAPI_NODE_PROPERTY_STRUCTURAL_BYTES: u64 = 512;
const REAPI_AUXILIARY_METADATA_STRUCTURAL_BYTES: u64 = 512;
// This duplicates Tonic's five-byte gRPC envelope so memory is admitted before
// Tonic retains and decodes each message. Keep it aligned with Tonic's decoder:
// https://github.com/hyperium/tonic/blob/v0.14.5/tonic/src/codec/decode.rs
pub(super) const GRPC_MESSAGE_HEADER_BYTES: usize = 5;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum GrpcWriteShapePolicy {
    ByteStream,
    BatchUpdate,
    ActionUpdate,
}

impl GrpcWriteShapePolicy {
    pub(super) fn decode_copy_multiplier(self) -> u64 {
        match self {
            Self::ByteStream => BYTESTREAM_WRITE_DECODE_COPIES,
            Self::BatchUpdate => CAS_BATCH_UPDATE_DECODE_COPIES,
            Self::ActionUpdate => ACTION_CACHE_UPDATE_DECODE_COPIES,
        }
    }

    pub(super) fn is_unary(self) -> bool {
        self != Self::ByteStream
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(super) struct DecodeShape {
    pub(super) structural_bytes: u64,
    retained_bytes: u64,
}

impl DecodeShape {
    fn add_structural(&mut self, bytes: u64) -> Result<(), Status> {
        self.structural_bytes = self.structural_bytes.checked_add(bytes).ok_or_else(|| {
            Status::resource_exhausted("remote-execution request structure exceeds server limits")
        })?;
        Ok(())
    }

    fn add_retained(&mut self, bytes: usize) -> Result<(), Status> {
        self.retained_bytes = self
            .retained_bytes
            .checked_add(bytes as u64)
            .ok_or_else(|| {
                Status::resource_exhausted(
                    "remote-execution request retained data exceeds server limits",
                )
            })?;
        Ok(())
    }

    fn add_output(&mut self) -> Result<(), Status> {
        self.add_structural(REAPI_ACTION_OUTPUT_STRUCTURAL_BYTES)
    }

    fn add_node_property(&mut self) -> Result<(), Status> {
        self.add_structural(REAPI_NODE_PROPERTY_STRUCTURAL_BYTES)
    }

    fn add_auxiliary_metadata(&mut self) -> Result<(), Status> {
        self.add_structural(REAPI_AUXILIARY_METADATA_STRUCTURAL_BYTES)
    }

    pub(super) fn estimated_decoded_bytes(self) -> u64 {
        self.structural_bytes
            .saturating_add(self.retained_bytes)
            .max(1)
    }
}

enum ProtoField<'a> {
    Varint { number: u32 },
    Fixed { number: u32 },
    Bytes { number: u32, value: &'a [u8] },
}

struct ProtoCursor<'a> {
    bytes: &'a [u8],
    offset: usize,
}

const PROTOBUF_RECURSION_LIMIT: usize = 100;

impl<'a> ProtoCursor<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, offset: 0 }
    }

    fn next(&mut self) -> Result<Option<ProtoField<'a>>, Status> {
        if self.offset == self.bytes.len() {
            return Ok(None);
        }
        let key = self.read_varint()?;
        let number = u32::try_from(key >> 3)
            .ok()
            .filter(|number| *number != 0 && *number <= 0x1fff_ffff)
            .ok_or_else(|| Status::invalid_argument("invalid Protocol Buffers field number"))?;
        match key & 7 {
            0 => {
                self.read_varint()?;
                Ok(Some(ProtoField::Varint { number }))
            }
            1 => {
                self.skip(8)?;
                Ok(Some(ProtoField::Fixed { number }))
            }
            2 => {
                let length = usize::try_from(self.read_varint()?).map_err(|_| {
                    Status::invalid_argument("Protocol Buffers field length does not fit in memory")
                })?;
                let end = self.offset.checked_add(length).ok_or_else(|| {
                    Status::invalid_argument("Protocol Buffers field length overflow")
                })?;
                let value = self.bytes.get(self.offset..end).ok_or_else(|| {
                    Status::invalid_argument("truncated Protocol Buffers length-delimited field")
                })?;
                self.offset = end;
                Ok(Some(ProtoField::Bytes { number, value }))
            }
            3 => {
                self.skip_group(number)?;
                Ok(Some(ProtoField::Fixed { number }))
            }
            4 => Err(Status::invalid_argument(
                "unexpected Protocol Buffers end-group field",
            )),
            5 => {
                self.skip(4)?;
                Ok(Some(ProtoField::Fixed { number }))
            }
            _ => Err(Status::invalid_argument(
                "unsupported Protocol Buffers wire type",
            )),
        }
    }

    fn skip_group(&mut self, number: u32) -> Result<(), Status> {
        let mut groups = vec![number];
        loop {
            let key = self.read_varint()?;
            let number = u32::try_from(key >> 3)
                .ok()
                .filter(|number| *number != 0 && *number <= 0x1fff_ffff)
                .ok_or_else(|| Status::invalid_argument("invalid Protocol Buffers field number"))?;
            match key & 7 {
                0 => {
                    self.read_varint()?;
                }
                1 => self.skip(8)?,
                2 => {
                    let length = usize::try_from(self.read_varint()?).map_err(|_| {
                        Status::invalid_argument(
                            "Protocol Buffers field length does not fit in memory",
                        )
                    })?;
                    self.skip(length)?;
                }
                3 => {
                    if groups.len() == PROTOBUF_RECURSION_LIMIT {
                        return Err(Status::invalid_argument(
                            "Protocol Buffers recursion limit reached",
                        ));
                    }
                    groups.push(number);
                }
                4 => {
                    if groups.pop() != Some(number) {
                        return Err(Status::invalid_argument(
                            "unexpected Protocol Buffers end-group field",
                        ));
                    }
                    if groups.is_empty() {
                        return Ok(());
                    }
                }
                5 => self.skip(4)?,
                _ => {
                    return Err(Status::invalid_argument(
                        "unsupported Protocol Buffers wire type",
                    ));
                }
            }
        }
    }

    fn read_varint(&mut self) -> Result<u64, Status> {
        let mut value = 0_u64;
        for shift in (0..70).step_by(7) {
            let byte = *self
                .bytes
                .get(self.offset)
                .ok_or_else(|| Status::invalid_argument("truncated Protocol Buffers varint"))?;
            self.offset += 1;
            if shift == 63 && byte > 1 {
                return Err(Status::invalid_argument("Protocol Buffers varint overflow"));
            }
            value |= u64::from(byte & 0x7f) << shift;
            if byte & 0x80 == 0 {
                return Ok(value);
            }
        }
        Err(Status::invalid_argument("Protocol Buffers varint overflow"))
    }

    fn skip(&mut self, bytes: usize) -> Result<(), Status> {
        self.offset = self
            .offset
            .checked_add(bytes)
            .filter(|offset| *offset <= self.bytes.len())
            .ok_or_else(|| Status::invalid_argument("truncated Protocol Buffers fixed field"))?;
        Ok(())
    }
}

fn check_string(value: &[u8], name: &str) -> Result<(), Status> {
    std::str::from_utf8(value)
        .map(|_| ())
        .map_err(|_| Status::invalid_argument(format!("{name} is not valid UTF-8")))
}

fn inspect_digest_wire(bytes: &[u8], shape: &mut DecodeShape) -> Result<(), Status> {
    let mut cursor = ProtoCursor::new(bytes);
    while let Some(field) = cursor.next()? {
        match field {
            ProtoField::Bytes { number: 1, value } => {
                check_string(value, "digest hash")?;
                shape.add_retained(value.len())?;
            }
            ProtoField::Varint { number: 2 } => {}
            ProtoField::Bytes { number: 2, .. }
            | ProtoField::Varint { number: 1 }
            | ProtoField::Fixed { number: 1 | 2 } => {
                return Err(Status::invalid_argument(
                    "digest field has the wrong Protocol Buffers wire type",
                ));
            }
            _ => {}
        }
    }
    Ok(())
}

pub(super) fn inspect_batch_update_wire(bytes: &[u8]) -> Result<DecodeShape, Status> {
    let mut cursor = ProtoCursor::new(bytes);
    let mut shape = DecodeShape::default();
    while let Some(field) = cursor.next()? {
        match field {
            ProtoField::Bytes { number: 1, value } => {
                check_string(value, "instance name")?;
            }
            ProtoField::Bytes { number: 2, value } => {
                shape.add_structural(REAPI_BATCH_REQUEST_STRUCTURAL_BYTES)?;
                let mut request = ProtoCursor::new(value);
                while let Some(field) = request.next()? {
                    match field {
                        ProtoField::Bytes { number: 1, value } => {
                            inspect_digest_wire(value, &mut shape)?;
                        }
                        ProtoField::Bytes { number: 2, .. } => {}
                        ProtoField::Varint { number: 3 } => {}
                        ProtoField::Bytes { number: 3, .. }
                        | ProtoField::Varint { number: 1 | 2 }
                        | ProtoField::Fixed { number: 1..=3 } => {
                            return Err(Status::invalid_argument(
                                "batch update request field has the wrong Protocol Buffers wire type",
                            ));
                        }
                        _ => {}
                    }
                }
            }
            ProtoField::Varint { number: 5 } => {}
            ProtoField::Bytes { number: 5, .. }
            | ProtoField::Varint { number: 1 | 2 }
            | ProtoField::Fixed { number: 1 | 2 | 5 } => {
                return Err(Status::invalid_argument(
                    "batch update field has the wrong Protocol Buffers wire type",
                ));
            }
            _ => {}
        }
    }
    Ok(shape)
}

fn inspect_node_properties_wire(bytes: &[u8], shape: &mut DecodeShape) -> Result<(), Status> {
    let mut cursor = ProtoCursor::new(bytes);
    while let Some(field) = cursor.next()? {
        if let ProtoField::Bytes { number: 1, value } = field {
            shape.add_node_property()?;
            let mut property = ProtoCursor::new(value);
            while let Some(field) = property.next()? {
                match field {
                    ProtoField::Bytes {
                        number: 1 | 2,
                        value,
                    } => {
                        check_string(value, "node property")?;
                        shape.add_retained(value.len())?;
                    }
                    ProtoField::Varint { number: 1 | 2 } | ProtoField::Fixed { number: 1 | 2 } => {
                        return Err(Status::invalid_argument(
                            "node property has the wrong Protocol Buffers wire type",
                        ));
                    }
                    _ => {}
                }
            }
        } else if matches!(
            field,
            ProtoField::Varint { number: 1 } | ProtoField::Fixed { number: 1 }
        ) {
            return Err(Status::invalid_argument(
                "node properties field has the wrong Protocol Buffers wire type",
            ));
        }
    }
    Ok(())
}

fn inspect_output_file_wire(bytes: &[u8], shape: &mut DecodeShape) -> Result<(), Status> {
    let mut cursor = ProtoCursor::new(bytes);
    while let Some(field) = cursor.next()? {
        match field {
            ProtoField::Bytes { number: 1, value } => {
                check_string(value, "output path")?;
                shape.add_retained(value.len())?;
            }
            ProtoField::Bytes { number: 2, value } => inspect_digest_wire(value, shape)?,
            ProtoField::Varint { number: 4 } => {}
            ProtoField::Bytes { number: 5, value } => shape.add_retained(value.len())?,
            ProtoField::Bytes { number: 7, value } => inspect_node_properties_wire(value, shape)?,
            ProtoField::Bytes { number: 4, .. }
            | ProtoField::Varint {
                number: 1 | 2 | 5 | 7,
            }
            | ProtoField::Fixed {
                number: 1 | 2 | 4 | 5 | 7,
            } => {
                return Err(Status::invalid_argument(
                    "output file field has the wrong Protocol Buffers wire type",
                ));
            }
            _ => {}
        }
    }
    Ok(())
}

fn inspect_output_directory_wire(bytes: &[u8], shape: &mut DecodeShape) -> Result<(), Status> {
    let mut cursor = ProtoCursor::new(bytes);
    while let Some(field) = cursor.next()? {
        match field {
            ProtoField::Bytes { number: 1, value } => {
                check_string(value, "output path")?;
                shape.add_retained(value.len())?;
            }
            ProtoField::Bytes {
                number: 3 | 5,
                value,
            } => inspect_digest_wire(value, shape)?,
            ProtoField::Varint { number: 1 | 3 | 5 } | ProtoField::Fixed { number: 1 | 3 | 5 } => {
                return Err(Status::invalid_argument(
                    "output directory field has the wrong Protocol Buffers wire type",
                ));
            }
            _ => {}
        }
    }
    Ok(())
}

fn inspect_output_symlink_wire(bytes: &[u8], shape: &mut DecodeShape) -> Result<(), Status> {
    let mut cursor = ProtoCursor::new(bytes);
    while let Some(field) = cursor.next()? {
        match field {
            ProtoField::Bytes {
                number: 1 | 2,
                value,
            } => {
                check_string(value, "output path or symlink target")?;
                shape.add_retained(value.len())?;
            }
            ProtoField::Bytes { number: 4, value } => inspect_node_properties_wire(value, shape)?,
            ProtoField::Varint { number: 1 | 2 | 4 } | ProtoField::Fixed { number: 1 | 2 | 4 } => {
                return Err(Status::invalid_argument(
                    "output symlink field has the wrong Protocol Buffers wire type",
                ));
            }
            _ => {}
        }
    }
    Ok(())
}

fn inspect_execution_metadata_wire(bytes: &[u8], shape: &mut DecodeShape) -> Result<(), Status> {
    let mut cursor = ProtoCursor::new(bytes);
    while let Some(field) = cursor.next()? {
        match field {
            ProtoField::Bytes { number: 1, value } => {
                check_string(value, "worker name")?;
                shape.add_retained(value.len())?;
            }
            ProtoField::Bytes { number: 11, value } => {
                shape.add_auxiliary_metadata()?;
                let mut any = ProtoCursor::new(value);
                while let Some(field) = any.next()? {
                    match field {
                        ProtoField::Bytes { number: 1, value } => {
                            check_string(value, "metadata type URL")?;
                            shape.add_retained(value.len())?;
                        }
                        ProtoField::Bytes { number: 2, value } => {
                            shape.add_retained(value.len())?
                        }
                        ProtoField::Varint { number: 1 | 2 }
                        | ProtoField::Fixed { number: 1 | 2 } => {
                            return Err(Status::invalid_argument(
                                "auxiliary metadata field has the wrong Protocol Buffers wire type",
                            ));
                        }
                        _ => {}
                    }
                }
            }
            ProtoField::Varint { number: 1 | 11 } | ProtoField::Fixed { number: 1 | 11 } => {
                return Err(Status::invalid_argument(
                    "execution metadata field has the wrong Protocol Buffers wire type",
                ));
            }
            _ => {}
        }
    }
    Ok(())
}

pub(super) fn inspect_action_result_wire(bytes: &[u8]) -> Result<DecodeShape, Status> {
    let mut cursor = ProtoCursor::new(bytes);
    let mut shape = DecodeShape::default();
    while let Some(field) = cursor.next()? {
        match field {
            ProtoField::Bytes { number: 2, value } => {
                shape.add_output()?;
                inspect_output_file_wire(value, &mut shape)?;
            }
            ProtoField::Bytes { number: 3, value } => {
                shape.add_output()?;
                inspect_output_directory_wire(value, &mut shape)?;
            }
            ProtoField::Bytes {
                number: 10..=12,
                value,
            } => {
                shape.add_output()?;
                inspect_output_symlink_wire(value, &mut shape)?;
            }
            ProtoField::Varint { number: 4 } => {}
            ProtoField::Bytes {
                number: 5 | 7,
                value,
            } => shape.add_retained(value.len())?,
            ProtoField::Bytes {
                number: 6 | 8,
                value,
            } => inspect_digest_wire(value, &mut shape)?,
            ProtoField::Bytes { number: 9, value } => {
                inspect_execution_metadata_wire(value, &mut shape)?
            }
            ProtoField::Bytes { number: 4, .. }
            | ProtoField::Varint {
                number: 2..=3 | 5..=12,
            }
            | ProtoField::Fixed { number: 2..=12 } => {
                return Err(Status::invalid_argument(
                    "action result field has the wrong Protocol Buffers wire type",
                ));
            }
            _ => {}
        }
    }
    Ok(shape)
}

pub(super) fn inspect_action_update_wire(bytes: &[u8]) -> Result<DecodeShape, Status> {
    let mut cursor = ProtoCursor::new(bytes);
    let mut shape = DecodeShape::default();
    while let Some(field) = cursor.next()? {
        match field {
            ProtoField::Bytes { number: 1, value } => {
                check_string(value, "instance name")?;
            }
            ProtoField::Bytes { number: 2, value } => inspect_digest_wire(value, &mut shape)?,
            ProtoField::Bytes { number: 3, value } => {
                let action_shape = inspect_action_result_wire(value)?;
                shape.add_structural(action_shape.structural_bytes)?;
                shape.retained_bytes = shape
                    .retained_bytes
                    .checked_add(action_shape.retained_bytes)
                    .ok_or_else(|| {
                        Status::resource_exhausted(
                            "remote-execution request retained data exceeds server limits",
                        )
                    })?;
            }
            ProtoField::Bytes { number: 4, .. } | ProtoField::Varint { number: 5 } => {}
            ProtoField::Varint { number: 1..=4 } | ProtoField::Fixed { number: 1..=5 } => {
                return Err(Status::invalid_argument(
                    "action update field has the wrong Protocol Buffers wire type",
                ));
            }
            _ => {}
        }
    }
    Ok(shape)
}
