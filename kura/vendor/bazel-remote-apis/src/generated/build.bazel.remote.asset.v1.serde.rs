impl serde::Serialize for FetchBlobRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.instance_name.is_empty() {
            len += 1;
        }
        if self.timeout.is_some() {
            len += 1;
        }
        if self.oldest_content_accepted.is_some() {
            len += 1;
        }
        if !self.uris.is_empty() {
            len += 1;
        }
        if !self.qualifiers.is_empty() {
            len += 1;
        }
        if self.digest_function != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.asset.v1.FetchBlobRequest", len)?;
        if !self.instance_name.is_empty() {
            struct_ser.serialize_field("instanceName", &self.instance_name)?;
        }
        if let Some(v) = self.timeout.as_ref() {
            struct_ser.serialize_field("timeout", v)?;
        }
        if let Some(v) = self.oldest_content_accepted.as_ref() {
            struct_ser.serialize_field("oldestContentAccepted", v)?;
        }
        if !self.uris.is_empty() {
            struct_ser.serialize_field("uris", &self.uris)?;
        }
        if !self.qualifiers.is_empty() {
            struct_ser.serialize_field("qualifiers", &self.qualifiers)?;
        }
        if self.digest_function != 0 {
            let v = super::super::execution::v2::digest_function::Value::try_from(self.digest_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.digest_function)))?;
            struct_ser.serialize_field("digestFunction", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for FetchBlobRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "instance_name",
            "instanceName",
            "timeout",
            "oldest_content_accepted",
            "oldestContentAccepted",
            "uris",
            "qualifiers",
            "digest_function",
            "digestFunction",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            InstanceName,
            Timeout,
            OldestContentAccepted,
            Uris,
            Qualifiers,
            DigestFunction,
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
                            "instanceName" | "instance_name" => Ok(GeneratedField::InstanceName),
                            "timeout" => Ok(GeneratedField::Timeout),
                            "oldestContentAccepted" | "oldest_content_accepted" => Ok(GeneratedField::OldestContentAccepted),
                            "uris" => Ok(GeneratedField::Uris),
                            "qualifiers" => Ok(GeneratedField::Qualifiers),
                            "digestFunction" | "digest_function" => Ok(GeneratedField::DigestFunction),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = FetchBlobRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.asset.v1.FetchBlobRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<FetchBlobRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut instance_name__ = None;
                let mut timeout__ = None;
                let mut oldest_content_accepted__ = None;
                let mut uris__ = None;
                let mut qualifiers__ = None;
                let mut digest_function__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::InstanceName => {
                            if instance_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("instanceName"));
                            }
                            instance_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Timeout => {
                            if timeout__.is_some() {
                                return Err(serde::de::Error::duplicate_field("timeout"));
                            }
                            timeout__ = map_.next_value()?;
                        }
                        GeneratedField::OldestContentAccepted => {
                            if oldest_content_accepted__.is_some() {
                                return Err(serde::de::Error::duplicate_field("oldestContentAccepted"));
                            }
                            oldest_content_accepted__ = map_.next_value()?;
                        }
                        GeneratedField::Uris => {
                            if uris__.is_some() {
                                return Err(serde::de::Error::duplicate_field("uris"));
                            }
                            uris__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Qualifiers => {
                            if qualifiers__.is_some() {
                                return Err(serde::de::Error::duplicate_field("qualifiers"));
                            }
                            qualifiers__ = Some(map_.next_value()?);
                        }
                        GeneratedField::DigestFunction => {
                            if digest_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digestFunction"));
                            }
                            digest_function__ = Some(map_.next_value::<super::super::execution::v2::digest_function::Value>()? as i32);
                        }
                    }
                }
                Ok(FetchBlobRequest {
                    instance_name: instance_name__.unwrap_or_default(),
                    timeout: timeout__,
                    oldest_content_accepted: oldest_content_accepted__,
                    uris: uris__.unwrap_or_default(),
                    qualifiers: qualifiers__.unwrap_or_default(),
                    digest_function: digest_function__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.asset.v1.FetchBlobRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for FetchBlobResponse {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.status.is_some() {
            len += 1;
        }
        if !self.uri.is_empty() {
            len += 1;
        }
        if !self.qualifiers.is_empty() {
            len += 1;
        }
        if self.expires_at.is_some() {
            len += 1;
        }
        if self.blob_digest.is_some() {
            len += 1;
        }
        if self.digest_function != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.asset.v1.FetchBlobResponse", len)?;
        if let Some(v) = self.status.as_ref() {
            struct_ser.serialize_field("status", v)?;
        }
        if !self.uri.is_empty() {
            struct_ser.serialize_field("uri", &self.uri)?;
        }
        if !self.qualifiers.is_empty() {
            struct_ser.serialize_field("qualifiers", &self.qualifiers)?;
        }
        if let Some(v) = self.expires_at.as_ref() {
            struct_ser.serialize_field("expiresAt", v)?;
        }
        if let Some(v) = self.blob_digest.as_ref() {
            struct_ser.serialize_field("blobDigest", v)?;
        }
        if self.digest_function != 0 {
            let v = super::super::execution::v2::digest_function::Value::try_from(self.digest_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.digest_function)))?;
            struct_ser.serialize_field("digestFunction", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for FetchBlobResponse {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "status",
            "uri",
            "qualifiers",
            "expires_at",
            "expiresAt",
            "blob_digest",
            "blobDigest",
            "digest_function",
            "digestFunction",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Status,
            Uri,
            Qualifiers,
            ExpiresAt,
            BlobDigest,
            DigestFunction,
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
                            "status" => Ok(GeneratedField::Status),
                            "uri" => Ok(GeneratedField::Uri),
                            "qualifiers" => Ok(GeneratedField::Qualifiers),
                            "expiresAt" | "expires_at" => Ok(GeneratedField::ExpiresAt),
                            "blobDigest" | "blob_digest" => Ok(GeneratedField::BlobDigest),
                            "digestFunction" | "digest_function" => Ok(GeneratedField::DigestFunction),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = FetchBlobResponse;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.asset.v1.FetchBlobResponse")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<FetchBlobResponse, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut status__ = None;
                let mut uri__ = None;
                let mut qualifiers__ = None;
                let mut expires_at__ = None;
                let mut blob_digest__ = None;
                let mut digest_function__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Status => {
                            if status__.is_some() {
                                return Err(serde::de::Error::duplicate_field("status"));
                            }
                            status__ = map_.next_value()?;
                        }
                        GeneratedField::Uri => {
                            if uri__.is_some() {
                                return Err(serde::de::Error::duplicate_field("uri"));
                            }
                            uri__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Qualifiers => {
                            if qualifiers__.is_some() {
                                return Err(serde::de::Error::duplicate_field("qualifiers"));
                            }
                            qualifiers__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ExpiresAt => {
                            if expires_at__.is_some() {
                                return Err(serde::de::Error::duplicate_field("expiresAt"));
                            }
                            expires_at__ = map_.next_value()?;
                        }
                        GeneratedField::BlobDigest => {
                            if blob_digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("blobDigest"));
                            }
                            blob_digest__ = map_.next_value()?;
                        }
                        GeneratedField::DigestFunction => {
                            if digest_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digestFunction"));
                            }
                            digest_function__ = Some(map_.next_value::<super::super::execution::v2::digest_function::Value>()? as i32);
                        }
                    }
                }
                Ok(FetchBlobResponse {
                    status: status__,
                    uri: uri__.unwrap_or_default(),
                    qualifiers: qualifiers__.unwrap_or_default(),
                    expires_at: expires_at__,
                    blob_digest: blob_digest__,
                    digest_function: digest_function__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.asset.v1.FetchBlobResponse", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for FetchDirectoryRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.instance_name.is_empty() {
            len += 1;
        }
        if self.timeout.is_some() {
            len += 1;
        }
        if self.oldest_content_accepted.is_some() {
            len += 1;
        }
        if !self.uris.is_empty() {
            len += 1;
        }
        if !self.qualifiers.is_empty() {
            len += 1;
        }
        if self.digest_function != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.asset.v1.FetchDirectoryRequest", len)?;
        if !self.instance_name.is_empty() {
            struct_ser.serialize_field("instanceName", &self.instance_name)?;
        }
        if let Some(v) = self.timeout.as_ref() {
            struct_ser.serialize_field("timeout", v)?;
        }
        if let Some(v) = self.oldest_content_accepted.as_ref() {
            struct_ser.serialize_field("oldestContentAccepted", v)?;
        }
        if !self.uris.is_empty() {
            struct_ser.serialize_field("uris", &self.uris)?;
        }
        if !self.qualifiers.is_empty() {
            struct_ser.serialize_field("qualifiers", &self.qualifiers)?;
        }
        if self.digest_function != 0 {
            let v = super::super::execution::v2::digest_function::Value::try_from(self.digest_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.digest_function)))?;
            struct_ser.serialize_field("digestFunction", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for FetchDirectoryRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "instance_name",
            "instanceName",
            "timeout",
            "oldest_content_accepted",
            "oldestContentAccepted",
            "uris",
            "qualifiers",
            "digest_function",
            "digestFunction",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            InstanceName,
            Timeout,
            OldestContentAccepted,
            Uris,
            Qualifiers,
            DigestFunction,
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
                            "instanceName" | "instance_name" => Ok(GeneratedField::InstanceName),
                            "timeout" => Ok(GeneratedField::Timeout),
                            "oldestContentAccepted" | "oldest_content_accepted" => Ok(GeneratedField::OldestContentAccepted),
                            "uris" => Ok(GeneratedField::Uris),
                            "qualifiers" => Ok(GeneratedField::Qualifiers),
                            "digestFunction" | "digest_function" => Ok(GeneratedField::DigestFunction),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = FetchDirectoryRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.asset.v1.FetchDirectoryRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<FetchDirectoryRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut instance_name__ = None;
                let mut timeout__ = None;
                let mut oldest_content_accepted__ = None;
                let mut uris__ = None;
                let mut qualifiers__ = None;
                let mut digest_function__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::InstanceName => {
                            if instance_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("instanceName"));
                            }
                            instance_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Timeout => {
                            if timeout__.is_some() {
                                return Err(serde::de::Error::duplicate_field("timeout"));
                            }
                            timeout__ = map_.next_value()?;
                        }
                        GeneratedField::OldestContentAccepted => {
                            if oldest_content_accepted__.is_some() {
                                return Err(serde::de::Error::duplicate_field("oldestContentAccepted"));
                            }
                            oldest_content_accepted__ = map_.next_value()?;
                        }
                        GeneratedField::Uris => {
                            if uris__.is_some() {
                                return Err(serde::de::Error::duplicate_field("uris"));
                            }
                            uris__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Qualifiers => {
                            if qualifiers__.is_some() {
                                return Err(serde::de::Error::duplicate_field("qualifiers"));
                            }
                            qualifiers__ = Some(map_.next_value()?);
                        }
                        GeneratedField::DigestFunction => {
                            if digest_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digestFunction"));
                            }
                            digest_function__ = Some(map_.next_value::<super::super::execution::v2::digest_function::Value>()? as i32);
                        }
                    }
                }
                Ok(FetchDirectoryRequest {
                    instance_name: instance_name__.unwrap_or_default(),
                    timeout: timeout__,
                    oldest_content_accepted: oldest_content_accepted__,
                    uris: uris__.unwrap_or_default(),
                    qualifiers: qualifiers__.unwrap_or_default(),
                    digest_function: digest_function__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.asset.v1.FetchDirectoryRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for FetchDirectoryResponse {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.status.is_some() {
            len += 1;
        }
        if !self.uri.is_empty() {
            len += 1;
        }
        if !self.qualifiers.is_empty() {
            len += 1;
        }
        if self.expires_at.is_some() {
            len += 1;
        }
        if self.root_directory_digest.is_some() {
            len += 1;
        }
        if self.digest_function != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.asset.v1.FetchDirectoryResponse", len)?;
        if let Some(v) = self.status.as_ref() {
            struct_ser.serialize_field("status", v)?;
        }
        if !self.uri.is_empty() {
            struct_ser.serialize_field("uri", &self.uri)?;
        }
        if !self.qualifiers.is_empty() {
            struct_ser.serialize_field("qualifiers", &self.qualifiers)?;
        }
        if let Some(v) = self.expires_at.as_ref() {
            struct_ser.serialize_field("expiresAt", v)?;
        }
        if let Some(v) = self.root_directory_digest.as_ref() {
            struct_ser.serialize_field("rootDirectoryDigest", v)?;
        }
        if self.digest_function != 0 {
            let v = super::super::execution::v2::digest_function::Value::try_from(self.digest_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.digest_function)))?;
            struct_ser.serialize_field("digestFunction", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for FetchDirectoryResponse {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "status",
            "uri",
            "qualifiers",
            "expires_at",
            "expiresAt",
            "root_directory_digest",
            "rootDirectoryDigest",
            "digest_function",
            "digestFunction",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Status,
            Uri,
            Qualifiers,
            ExpiresAt,
            RootDirectoryDigest,
            DigestFunction,
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
                            "status" => Ok(GeneratedField::Status),
                            "uri" => Ok(GeneratedField::Uri),
                            "qualifiers" => Ok(GeneratedField::Qualifiers),
                            "expiresAt" | "expires_at" => Ok(GeneratedField::ExpiresAt),
                            "rootDirectoryDigest" | "root_directory_digest" => Ok(GeneratedField::RootDirectoryDigest),
                            "digestFunction" | "digest_function" => Ok(GeneratedField::DigestFunction),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = FetchDirectoryResponse;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.asset.v1.FetchDirectoryResponse")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<FetchDirectoryResponse, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut status__ = None;
                let mut uri__ = None;
                let mut qualifiers__ = None;
                let mut expires_at__ = None;
                let mut root_directory_digest__ = None;
                let mut digest_function__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Status => {
                            if status__.is_some() {
                                return Err(serde::de::Error::duplicate_field("status"));
                            }
                            status__ = map_.next_value()?;
                        }
                        GeneratedField::Uri => {
                            if uri__.is_some() {
                                return Err(serde::de::Error::duplicate_field("uri"));
                            }
                            uri__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Qualifiers => {
                            if qualifiers__.is_some() {
                                return Err(serde::de::Error::duplicate_field("qualifiers"));
                            }
                            qualifiers__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ExpiresAt => {
                            if expires_at__.is_some() {
                                return Err(serde::de::Error::duplicate_field("expiresAt"));
                            }
                            expires_at__ = map_.next_value()?;
                        }
                        GeneratedField::RootDirectoryDigest => {
                            if root_directory_digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("rootDirectoryDigest"));
                            }
                            root_directory_digest__ = map_.next_value()?;
                        }
                        GeneratedField::DigestFunction => {
                            if digest_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digestFunction"));
                            }
                            digest_function__ = Some(map_.next_value::<super::super::execution::v2::digest_function::Value>()? as i32);
                        }
                    }
                }
                Ok(FetchDirectoryResponse {
                    status: status__,
                    uri: uri__.unwrap_or_default(),
                    qualifiers: qualifiers__.unwrap_or_default(),
                    expires_at: expires_at__,
                    root_directory_digest: root_directory_digest__,
                    digest_function: digest_function__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.asset.v1.FetchDirectoryResponse", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for PushBlobRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.instance_name.is_empty() {
            len += 1;
        }
        if !self.uris.is_empty() {
            len += 1;
        }
        if !self.qualifiers.is_empty() {
            len += 1;
        }
        if self.expire_at.is_some() {
            len += 1;
        }
        if self.blob_digest.is_some() {
            len += 1;
        }
        if !self.references_blobs.is_empty() {
            len += 1;
        }
        if !self.references_directories.is_empty() {
            len += 1;
        }
        if self.digest_function != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.asset.v1.PushBlobRequest", len)?;
        if !self.instance_name.is_empty() {
            struct_ser.serialize_field("instanceName", &self.instance_name)?;
        }
        if !self.uris.is_empty() {
            struct_ser.serialize_field("uris", &self.uris)?;
        }
        if !self.qualifiers.is_empty() {
            struct_ser.serialize_field("qualifiers", &self.qualifiers)?;
        }
        if let Some(v) = self.expire_at.as_ref() {
            struct_ser.serialize_field("expireAt", v)?;
        }
        if let Some(v) = self.blob_digest.as_ref() {
            struct_ser.serialize_field("blobDigest", v)?;
        }
        if !self.references_blobs.is_empty() {
            struct_ser.serialize_field("referencesBlobs", &self.references_blobs)?;
        }
        if !self.references_directories.is_empty() {
            struct_ser.serialize_field("referencesDirectories", &self.references_directories)?;
        }
        if self.digest_function != 0 {
            let v = super::super::execution::v2::digest_function::Value::try_from(self.digest_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.digest_function)))?;
            struct_ser.serialize_field("digestFunction", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for PushBlobRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "instance_name",
            "instanceName",
            "uris",
            "qualifiers",
            "expire_at",
            "expireAt",
            "blob_digest",
            "blobDigest",
            "references_blobs",
            "referencesBlobs",
            "references_directories",
            "referencesDirectories",
            "digest_function",
            "digestFunction",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            InstanceName,
            Uris,
            Qualifiers,
            ExpireAt,
            BlobDigest,
            ReferencesBlobs,
            ReferencesDirectories,
            DigestFunction,
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
                            "instanceName" | "instance_name" => Ok(GeneratedField::InstanceName),
                            "uris" => Ok(GeneratedField::Uris),
                            "qualifiers" => Ok(GeneratedField::Qualifiers),
                            "expireAt" | "expire_at" => Ok(GeneratedField::ExpireAt),
                            "blobDigest" | "blob_digest" => Ok(GeneratedField::BlobDigest),
                            "referencesBlobs" | "references_blobs" => Ok(GeneratedField::ReferencesBlobs),
                            "referencesDirectories" | "references_directories" => Ok(GeneratedField::ReferencesDirectories),
                            "digestFunction" | "digest_function" => Ok(GeneratedField::DigestFunction),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = PushBlobRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.asset.v1.PushBlobRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<PushBlobRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut instance_name__ = None;
                let mut uris__ = None;
                let mut qualifiers__ = None;
                let mut expire_at__ = None;
                let mut blob_digest__ = None;
                let mut references_blobs__ = None;
                let mut references_directories__ = None;
                let mut digest_function__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::InstanceName => {
                            if instance_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("instanceName"));
                            }
                            instance_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Uris => {
                            if uris__.is_some() {
                                return Err(serde::de::Error::duplicate_field("uris"));
                            }
                            uris__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Qualifiers => {
                            if qualifiers__.is_some() {
                                return Err(serde::de::Error::duplicate_field("qualifiers"));
                            }
                            qualifiers__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ExpireAt => {
                            if expire_at__.is_some() {
                                return Err(serde::de::Error::duplicate_field("expireAt"));
                            }
                            expire_at__ = map_.next_value()?;
                        }
                        GeneratedField::BlobDigest => {
                            if blob_digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("blobDigest"));
                            }
                            blob_digest__ = map_.next_value()?;
                        }
                        GeneratedField::ReferencesBlobs => {
                            if references_blobs__.is_some() {
                                return Err(serde::de::Error::duplicate_field("referencesBlobs"));
                            }
                            references_blobs__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ReferencesDirectories => {
                            if references_directories__.is_some() {
                                return Err(serde::de::Error::duplicate_field("referencesDirectories"));
                            }
                            references_directories__ = Some(map_.next_value()?);
                        }
                        GeneratedField::DigestFunction => {
                            if digest_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digestFunction"));
                            }
                            digest_function__ = Some(map_.next_value::<super::super::execution::v2::digest_function::Value>()? as i32);
                        }
                    }
                }
                Ok(PushBlobRequest {
                    instance_name: instance_name__.unwrap_or_default(),
                    uris: uris__.unwrap_or_default(),
                    qualifiers: qualifiers__.unwrap_or_default(),
                    expire_at: expire_at__,
                    blob_digest: blob_digest__,
                    references_blobs: references_blobs__.unwrap_or_default(),
                    references_directories: references_directories__.unwrap_or_default(),
                    digest_function: digest_function__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.asset.v1.PushBlobRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for PushBlobResponse {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let len = 0;
        let struct_ser = serializer.serialize_struct("build.bazel.remote.asset.v1.PushBlobResponse", len)?;
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for PushBlobResponse {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
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
                            Err(serde::de::Error::unknown_field(value, FIELDS))
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = PushBlobResponse;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.asset.v1.PushBlobResponse")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<PushBlobResponse, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                while map_.next_key::<GeneratedField>()?.is_some() {
                    let _ = map_.next_value::<serde::de::IgnoredAny>()?;
                }
                Ok(PushBlobResponse {
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.asset.v1.PushBlobResponse", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for PushDirectoryRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.instance_name.is_empty() {
            len += 1;
        }
        if !self.uris.is_empty() {
            len += 1;
        }
        if !self.qualifiers.is_empty() {
            len += 1;
        }
        if self.expire_at.is_some() {
            len += 1;
        }
        if self.root_directory_digest.is_some() {
            len += 1;
        }
        if !self.references_blobs.is_empty() {
            len += 1;
        }
        if !self.references_directories.is_empty() {
            len += 1;
        }
        if self.digest_function != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.asset.v1.PushDirectoryRequest", len)?;
        if !self.instance_name.is_empty() {
            struct_ser.serialize_field("instanceName", &self.instance_name)?;
        }
        if !self.uris.is_empty() {
            struct_ser.serialize_field("uris", &self.uris)?;
        }
        if !self.qualifiers.is_empty() {
            struct_ser.serialize_field("qualifiers", &self.qualifiers)?;
        }
        if let Some(v) = self.expire_at.as_ref() {
            struct_ser.serialize_field("expireAt", v)?;
        }
        if let Some(v) = self.root_directory_digest.as_ref() {
            struct_ser.serialize_field("rootDirectoryDigest", v)?;
        }
        if !self.references_blobs.is_empty() {
            struct_ser.serialize_field("referencesBlobs", &self.references_blobs)?;
        }
        if !self.references_directories.is_empty() {
            struct_ser.serialize_field("referencesDirectories", &self.references_directories)?;
        }
        if self.digest_function != 0 {
            let v = super::super::execution::v2::digest_function::Value::try_from(self.digest_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.digest_function)))?;
            struct_ser.serialize_field("digestFunction", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for PushDirectoryRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "instance_name",
            "instanceName",
            "uris",
            "qualifiers",
            "expire_at",
            "expireAt",
            "root_directory_digest",
            "rootDirectoryDigest",
            "references_blobs",
            "referencesBlobs",
            "references_directories",
            "referencesDirectories",
            "digest_function",
            "digestFunction",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            InstanceName,
            Uris,
            Qualifiers,
            ExpireAt,
            RootDirectoryDigest,
            ReferencesBlobs,
            ReferencesDirectories,
            DigestFunction,
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
                            "instanceName" | "instance_name" => Ok(GeneratedField::InstanceName),
                            "uris" => Ok(GeneratedField::Uris),
                            "qualifiers" => Ok(GeneratedField::Qualifiers),
                            "expireAt" | "expire_at" => Ok(GeneratedField::ExpireAt),
                            "rootDirectoryDigest" | "root_directory_digest" => Ok(GeneratedField::RootDirectoryDigest),
                            "referencesBlobs" | "references_blobs" => Ok(GeneratedField::ReferencesBlobs),
                            "referencesDirectories" | "references_directories" => Ok(GeneratedField::ReferencesDirectories),
                            "digestFunction" | "digest_function" => Ok(GeneratedField::DigestFunction),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = PushDirectoryRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.asset.v1.PushDirectoryRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<PushDirectoryRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut instance_name__ = None;
                let mut uris__ = None;
                let mut qualifiers__ = None;
                let mut expire_at__ = None;
                let mut root_directory_digest__ = None;
                let mut references_blobs__ = None;
                let mut references_directories__ = None;
                let mut digest_function__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::InstanceName => {
                            if instance_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("instanceName"));
                            }
                            instance_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Uris => {
                            if uris__.is_some() {
                                return Err(serde::de::Error::duplicate_field("uris"));
                            }
                            uris__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Qualifiers => {
                            if qualifiers__.is_some() {
                                return Err(serde::de::Error::duplicate_field("qualifiers"));
                            }
                            qualifiers__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ExpireAt => {
                            if expire_at__.is_some() {
                                return Err(serde::de::Error::duplicate_field("expireAt"));
                            }
                            expire_at__ = map_.next_value()?;
                        }
                        GeneratedField::RootDirectoryDigest => {
                            if root_directory_digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("rootDirectoryDigest"));
                            }
                            root_directory_digest__ = map_.next_value()?;
                        }
                        GeneratedField::ReferencesBlobs => {
                            if references_blobs__.is_some() {
                                return Err(serde::de::Error::duplicate_field("referencesBlobs"));
                            }
                            references_blobs__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ReferencesDirectories => {
                            if references_directories__.is_some() {
                                return Err(serde::de::Error::duplicate_field("referencesDirectories"));
                            }
                            references_directories__ = Some(map_.next_value()?);
                        }
                        GeneratedField::DigestFunction => {
                            if digest_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digestFunction"));
                            }
                            digest_function__ = Some(map_.next_value::<super::super::execution::v2::digest_function::Value>()? as i32);
                        }
                    }
                }
                Ok(PushDirectoryRequest {
                    instance_name: instance_name__.unwrap_or_default(),
                    uris: uris__.unwrap_or_default(),
                    qualifiers: qualifiers__.unwrap_or_default(),
                    expire_at: expire_at__,
                    root_directory_digest: root_directory_digest__,
                    references_blobs: references_blobs__.unwrap_or_default(),
                    references_directories: references_directories__.unwrap_or_default(),
                    digest_function: digest_function__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.asset.v1.PushDirectoryRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for PushDirectoryResponse {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let len = 0;
        let struct_ser = serializer.serialize_struct("build.bazel.remote.asset.v1.PushDirectoryResponse", len)?;
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for PushDirectoryResponse {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
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
                            Err(serde::de::Error::unknown_field(value, FIELDS))
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = PushDirectoryResponse;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.asset.v1.PushDirectoryResponse")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<PushDirectoryResponse, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                while map_.next_key::<GeneratedField>()?.is_some() {
                    let _ = map_.next_value::<serde::de::IgnoredAny>()?;
                }
                Ok(PushDirectoryResponse {
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.asset.v1.PushDirectoryResponse", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for Qualifier {
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
        if !self.value.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.asset.v1.Qualifier", len)?;
        if !self.name.is_empty() {
            struct_ser.serialize_field("name", &self.name)?;
        }
        if !self.value.is_empty() {
            struct_ser.serialize_field("value", &self.value)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for Qualifier {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "name",
            "value",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Name,
            Value,
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
                            "value" => Ok(GeneratedField::Value),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = Qualifier;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.asset.v1.Qualifier")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<Qualifier, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut name__ = None;
                let mut value__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Name => {
                            if name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("name"));
                            }
                            name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Value => {
                            if value__.is_some() {
                                return Err(serde::de::Error::duplicate_field("value"));
                            }
                            value__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(Qualifier {
                    name: name__.unwrap_or_default(),
                    value: value__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.asset.v1.Qualifier", FIELDS, GeneratedVisitor)
    }
}
