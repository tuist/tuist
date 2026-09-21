impl serde::Serialize for QueryWriteStatusRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.resource_name.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.bytestream.QueryWriteStatusRequest", len)?;
        if !self.resource_name.is_empty() {
            struct_ser.serialize_field("resourceName", &self.resource_name)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for QueryWriteStatusRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "resource_name",
            "resourceName",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            ResourceName,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "resourceName" | "resource_name" => Ok(GeneratedField::ResourceName),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = QueryWriteStatusRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.bytestream.QueryWriteStatusRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<QueryWriteStatusRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut resource_name__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::ResourceName => {
                            if resource_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("resourceName"));
                            }
                            resource_name__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(QueryWriteStatusRequest {
                    resource_name: resource_name__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("google.bytestream.QueryWriteStatusRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for QueryWriteStatusResponse {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.committed_size != 0 {
            len += 1;
        }
        if self.complete {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.bytestream.QueryWriteStatusResponse", len)?;
        if self.committed_size != 0 {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("committedSize", ToString::to_string(&self.committed_size).as_str())?;
        }
        if self.complete {
            struct_ser.serialize_field("complete", &self.complete)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for QueryWriteStatusResponse {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "committed_size",
            "committedSize",
            "complete",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            CommittedSize,
            Complete,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "committedSize" | "committed_size" => Ok(GeneratedField::CommittedSize),
                            "complete" => Ok(GeneratedField::Complete),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = QueryWriteStatusResponse;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.bytestream.QueryWriteStatusResponse")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<QueryWriteStatusResponse, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut committed_size__ = None;
                let mut complete__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::CommittedSize => {
                            if committed_size__.is_some() {
                                return Err(serde::de::Error::duplicate_field("committedSize"));
                            }
                            committed_size__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Complete => {
                            if complete__.is_some() {
                                return Err(serde::de::Error::duplicate_field("complete"));
                            }
                            complete__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(QueryWriteStatusResponse {
                    committed_size: committed_size__.unwrap_or_default(),
                    complete: complete__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("google.bytestream.QueryWriteStatusResponse", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ReadRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.resource_name.is_empty() {
            len += 1;
        }
        if self.read_offset != 0 {
            len += 1;
        }
        if self.read_limit != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.bytestream.ReadRequest", len)?;
        if !self.resource_name.is_empty() {
            struct_ser.serialize_field("resourceName", &self.resource_name)?;
        }
        if self.read_offset != 0 {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("readOffset", ToString::to_string(&self.read_offset).as_str())?;
        }
        if self.read_limit != 0 {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("readLimit", ToString::to_string(&self.read_limit).as_str())?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ReadRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "resource_name",
            "resourceName",
            "read_offset",
            "readOffset",
            "read_limit",
            "readLimit",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            ResourceName,
            ReadOffset,
            ReadLimit,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "resourceName" | "resource_name" => Ok(GeneratedField::ResourceName),
                            "readOffset" | "read_offset" => Ok(GeneratedField::ReadOffset),
                            "readLimit" | "read_limit" => Ok(GeneratedField::ReadLimit),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ReadRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.bytestream.ReadRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ReadRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut resource_name__ = None;
                let mut read_offset__ = None;
                let mut read_limit__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::ResourceName => {
                            if resource_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("resourceName"));
                            }
                            resource_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ReadOffset => {
                            if read_offset__.is_some() {
                                return Err(serde::de::Error::duplicate_field("readOffset"));
                            }
                            read_offset__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::ReadLimit => {
                            if read_limit__.is_some() {
                                return Err(serde::de::Error::duplicate_field("readLimit"));
                            }
                            read_limit__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                    }
                }
                Ok(ReadRequest {
                    resource_name: resource_name__.unwrap_or_default(),
                    read_offset: read_offset__.unwrap_or_default(),
                    read_limit: read_limit__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("google.bytestream.ReadRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ReadResponse {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.data.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.bytestream.ReadResponse", len)?;
        if !self.data.is_empty() {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("data", pbjson::private::base64::encode(&self.data).as_str())?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ReadResponse {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "data",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Data,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "data" => Ok(GeneratedField::Data),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ReadResponse;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.bytestream.ReadResponse")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ReadResponse, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut data__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Data => {
                            if data__.is_some() {
                                return Err(serde::de::Error::duplicate_field("data"));
                            }
                            data__ = 
                                Some(map_.next_value::<::pbjson::private::BytesDeserialize<_>>()?.0)
                            ;
                        }
                    }
                }
                Ok(ReadResponse {
                    data: data__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("google.bytestream.ReadResponse", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for WriteRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.resource_name.is_empty() {
            len += 1;
        }
        if self.write_offset != 0 {
            len += 1;
        }
        if self.finish_write {
            len += 1;
        }
        if !self.data.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.bytestream.WriteRequest", len)?;
        if !self.resource_name.is_empty() {
            struct_ser.serialize_field("resourceName", &self.resource_name)?;
        }
        if self.write_offset != 0 {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("writeOffset", ToString::to_string(&self.write_offset).as_str())?;
        }
        if self.finish_write {
            struct_ser.serialize_field("finishWrite", &self.finish_write)?;
        }
        if !self.data.is_empty() {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("data", pbjson::private::base64::encode(&self.data).as_str())?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for WriteRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "resource_name",
            "resourceName",
            "write_offset",
            "writeOffset",
            "finish_write",
            "finishWrite",
            "data",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            ResourceName,
            WriteOffset,
            FinishWrite,
            Data,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "resourceName" | "resource_name" => Ok(GeneratedField::ResourceName),
                            "writeOffset" | "write_offset" => Ok(GeneratedField::WriteOffset),
                            "finishWrite" | "finish_write" => Ok(GeneratedField::FinishWrite),
                            "data" => Ok(GeneratedField::Data),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = WriteRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.bytestream.WriteRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<WriteRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut resource_name__ = None;
                let mut write_offset__ = None;
                let mut finish_write__ = None;
                let mut data__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::ResourceName => {
                            if resource_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("resourceName"));
                            }
                            resource_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::WriteOffset => {
                            if write_offset__.is_some() {
                                return Err(serde::de::Error::duplicate_field("writeOffset"));
                            }
                            write_offset__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::FinishWrite => {
                            if finish_write__.is_some() {
                                return Err(serde::de::Error::duplicate_field("finishWrite"));
                            }
                            finish_write__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Data => {
                            if data__.is_some() {
                                return Err(serde::de::Error::duplicate_field("data"));
                            }
                            data__ = 
                                Some(map_.next_value::<::pbjson::private::BytesDeserialize<_>>()?.0)
                            ;
                        }
                    }
                }
                Ok(WriteRequest {
                    resource_name: resource_name__.unwrap_or_default(),
                    write_offset: write_offset__.unwrap_or_default(),
                    finish_write: finish_write__.unwrap_or_default(),
                    data: data__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("google.bytestream.WriteRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for WriteResponse {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.committed_size != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.bytestream.WriteResponse", len)?;
        if self.committed_size != 0 {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("committedSize", ToString::to_string(&self.committed_size).as_str())?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for WriteResponse {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "committed_size",
            "committedSize",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            CommittedSize,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "committedSize" | "committed_size" => Ok(GeneratedField::CommittedSize),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = WriteResponse;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.bytestream.WriteResponse")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<WriteResponse, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut committed_size__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::CommittedSize => {
                            if committed_size__.is_some() {
                                return Err(serde::de::Error::duplicate_field("committedSize"));
                            }
                            committed_size__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                    }
                }
                Ok(WriteResponse {
                    committed_size: committed_size__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("google.bytestream.WriteResponse", FIELDS, GeneratedVisitor)
    }
}
