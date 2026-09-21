impl serde::Serialize for CreateLogStreamRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.parent.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.logstream.v1.CreateLogStreamRequest", len)?;
        if !self.parent.is_empty() {
            struct_ser.serialize_field("parent", &self.parent)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for CreateLogStreamRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "parent",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Parent,
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
                            "parent" => Ok(GeneratedField::Parent),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = CreateLogStreamRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.logstream.v1.CreateLogStreamRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<CreateLogStreamRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut parent__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Parent => {
                            if parent__.is_some() {
                                return Err(serde::de::Error::duplicate_field("parent"));
                            }
                            parent__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(CreateLogStreamRequest {
                    parent: parent__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.logstream.v1.CreateLogStreamRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for LogStream {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.name.is_empty() {
            len += 1;
        }
        if !self.write_resource_name.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.logstream.v1.LogStream", len)?;
        if !self.name.is_empty() {
            struct_ser.serialize_field("name", &self.name)?;
        }
        if !self.write_resource_name.is_empty() {
            struct_ser.serialize_field("writeResourceName", &self.write_resource_name)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for LogStream {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "name",
            "write_resource_name",
            "writeResourceName",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Name,
            WriteResourceName,
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
                            "name" => Ok(GeneratedField::Name),
                            "writeResourceName" | "write_resource_name" => Ok(GeneratedField::WriteResourceName),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = LogStream;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.logstream.v1.LogStream")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<LogStream, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut name__ = None;
                let mut write_resource_name__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Name => {
                            if name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("name"));
                            }
                            name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::WriteResourceName => {
                            if write_resource_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("writeResourceName"));
                            }
                            write_resource_name__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(LogStream {
                    name: name__.unwrap_or_default(),
                    write_resource_name: write_resource_name__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.logstream.v1.LogStream", FIELDS, GeneratedVisitor)
    }
}
