impl serde::Serialize for Action {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.command_digest.is_some() {
            len += 1;
        }
        if self.input_root_digest.is_some() {
            len += 1;
        }
        if self.timeout.is_some() {
            len += 1;
        }
        if self.do_not_cache {
            len += 1;
        }
        if !self.salt.is_empty() {
            len += 1;
        }
        if self.platform.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.Action", len)?;
        if let Some(v) = self.command_digest.as_ref() {
            struct_ser.serialize_field("commandDigest", v)?;
        }
        if let Some(v) = self.input_root_digest.as_ref() {
            struct_ser.serialize_field("inputRootDigest", v)?;
        }
        if let Some(v) = self.timeout.as_ref() {
            struct_ser.serialize_field("timeout", v)?;
        }
        if self.do_not_cache {
            struct_ser.serialize_field("doNotCache", &self.do_not_cache)?;
        }
        if !self.salt.is_empty() {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("salt", pbjson::private::base64::encode(&self.salt).as_str())?;
        }
        if let Some(v) = self.platform.as_ref() {
            struct_ser.serialize_field("platform", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for Action {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "command_digest",
            "commandDigest",
            "input_root_digest",
            "inputRootDigest",
            "timeout",
            "do_not_cache",
            "doNotCache",
            "salt",
            "platform",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            CommandDigest,
            InputRootDigest,
            Timeout,
            DoNotCache,
            Salt,
            Platform,
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
                            "commandDigest" | "command_digest" => Ok(GeneratedField::CommandDigest),
                            "inputRootDigest" | "input_root_digest" => Ok(GeneratedField::InputRootDigest),
                            "timeout" => Ok(GeneratedField::Timeout),
                            "doNotCache" | "do_not_cache" => Ok(GeneratedField::DoNotCache),
                            "salt" => Ok(GeneratedField::Salt),
                            "platform" => Ok(GeneratedField::Platform),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = Action;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.Action")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<Action, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut command_digest__ = None;
                let mut input_root_digest__ = None;
                let mut timeout__ = None;
                let mut do_not_cache__ = None;
                let mut salt__ = None;
                let mut platform__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::CommandDigest => {
                            if command_digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("commandDigest"));
                            }
                            command_digest__ = map_.next_value()?;
                        }
                        GeneratedField::InputRootDigest => {
                            if input_root_digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("inputRootDigest"));
                            }
                            input_root_digest__ = map_.next_value()?;
                        }
                        GeneratedField::Timeout => {
                            if timeout__.is_some() {
                                return Err(serde::de::Error::duplicate_field("timeout"));
                            }
                            timeout__ = map_.next_value()?;
                        }
                        GeneratedField::DoNotCache => {
                            if do_not_cache__.is_some() {
                                return Err(serde::de::Error::duplicate_field("doNotCache"));
                            }
                            do_not_cache__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Salt => {
                            if salt__.is_some() {
                                return Err(serde::de::Error::duplicate_field("salt"));
                            }
                            salt__ = 
                                Some(map_.next_value::<::pbjson::private::BytesDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Platform => {
                            if platform__.is_some() {
                                return Err(serde::de::Error::duplicate_field("platform"));
                            }
                            platform__ = map_.next_value()?;
                        }
                    }
                }
                Ok(Action {
                    command_digest: command_digest__,
                    input_root_digest: input_root_digest__,
                    timeout: timeout__,
                    do_not_cache: do_not_cache__.unwrap_or_default(),
                    salt: salt__.unwrap_or_default(),
                    platform: platform__,
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.Action", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ActionCacheUpdateCapabilities {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.update_enabled {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.ActionCacheUpdateCapabilities", len)?;
        if self.update_enabled {
            struct_ser.serialize_field("updateEnabled", &self.update_enabled)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ActionCacheUpdateCapabilities {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "update_enabled",
            "updateEnabled",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            UpdateEnabled,
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
                            "updateEnabled" | "update_enabled" => Ok(GeneratedField::UpdateEnabled),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ActionCacheUpdateCapabilities;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.ActionCacheUpdateCapabilities")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ActionCacheUpdateCapabilities, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut update_enabled__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::UpdateEnabled => {
                            if update_enabled__.is_some() {
                                return Err(serde::de::Error::duplicate_field("updateEnabled"));
                            }
                            update_enabled__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(ActionCacheUpdateCapabilities {
                    update_enabled: update_enabled__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.ActionCacheUpdateCapabilities", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ActionResult {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.output_files.is_empty() {
            len += 1;
        }
        if !self.output_file_symlinks.is_empty() {
            len += 1;
        }
        if !self.output_symlinks.is_empty() {
            len += 1;
        }
        if !self.output_directories.is_empty() {
            len += 1;
        }
        if !self.output_directory_symlinks.is_empty() {
            len += 1;
        }
        if self.exit_code != 0 {
            len += 1;
        }
        if !self.stdout_raw.is_empty() {
            len += 1;
        }
        if self.stdout_digest.is_some() {
            len += 1;
        }
        if !self.stderr_raw.is_empty() {
            len += 1;
        }
        if self.stderr_digest.is_some() {
            len += 1;
        }
        if self.execution_metadata.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.ActionResult", len)?;
        if !self.output_files.is_empty() {
            struct_ser.serialize_field("outputFiles", &self.output_files)?;
        }
        if !self.output_file_symlinks.is_empty() {
            struct_ser.serialize_field("outputFileSymlinks", &self.output_file_symlinks)?;
        }
        if !self.output_symlinks.is_empty() {
            struct_ser.serialize_field("outputSymlinks", &self.output_symlinks)?;
        }
        if !self.output_directories.is_empty() {
            struct_ser.serialize_field("outputDirectories", &self.output_directories)?;
        }
        if !self.output_directory_symlinks.is_empty() {
            struct_ser.serialize_field("outputDirectorySymlinks", &self.output_directory_symlinks)?;
        }
        if self.exit_code != 0 {
            struct_ser.serialize_field("exitCode", &self.exit_code)?;
        }
        if !self.stdout_raw.is_empty() {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("stdoutRaw", pbjson::private::base64::encode(&self.stdout_raw).as_str())?;
        }
        if let Some(v) = self.stdout_digest.as_ref() {
            struct_ser.serialize_field("stdoutDigest", v)?;
        }
        if !self.stderr_raw.is_empty() {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("stderrRaw", pbjson::private::base64::encode(&self.stderr_raw).as_str())?;
        }
        if let Some(v) = self.stderr_digest.as_ref() {
            struct_ser.serialize_field("stderrDigest", v)?;
        }
        if let Some(v) = self.execution_metadata.as_ref() {
            struct_ser.serialize_field("executionMetadata", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ActionResult {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "output_files",
            "outputFiles",
            "output_file_symlinks",
            "outputFileSymlinks",
            "output_symlinks",
            "outputSymlinks",
            "output_directories",
            "outputDirectories",
            "output_directory_symlinks",
            "outputDirectorySymlinks",
            "exit_code",
            "exitCode",
            "stdout_raw",
            "stdoutRaw",
            "stdout_digest",
            "stdoutDigest",
            "stderr_raw",
            "stderrRaw",
            "stderr_digest",
            "stderrDigest",
            "execution_metadata",
            "executionMetadata",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            OutputFiles,
            OutputFileSymlinks,
            OutputSymlinks,
            OutputDirectories,
            OutputDirectorySymlinks,
            ExitCode,
            StdoutRaw,
            StdoutDigest,
            StderrRaw,
            StderrDigest,
            ExecutionMetadata,
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
                            "outputFiles" | "output_files" => Ok(GeneratedField::OutputFiles),
                            "outputFileSymlinks" | "output_file_symlinks" => Ok(GeneratedField::OutputFileSymlinks),
                            "outputSymlinks" | "output_symlinks" => Ok(GeneratedField::OutputSymlinks),
                            "outputDirectories" | "output_directories" => Ok(GeneratedField::OutputDirectories),
                            "outputDirectorySymlinks" | "output_directory_symlinks" => Ok(GeneratedField::OutputDirectorySymlinks),
                            "exitCode" | "exit_code" => Ok(GeneratedField::ExitCode),
                            "stdoutRaw" | "stdout_raw" => Ok(GeneratedField::StdoutRaw),
                            "stdoutDigest" | "stdout_digest" => Ok(GeneratedField::StdoutDigest),
                            "stderrRaw" | "stderr_raw" => Ok(GeneratedField::StderrRaw),
                            "stderrDigest" | "stderr_digest" => Ok(GeneratedField::StderrDigest),
                            "executionMetadata" | "execution_metadata" => Ok(GeneratedField::ExecutionMetadata),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ActionResult;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.ActionResult")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ActionResult, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut output_files__ = None;
                let mut output_file_symlinks__ = None;
                let mut output_symlinks__ = None;
                let mut output_directories__ = None;
                let mut output_directory_symlinks__ = None;
                let mut exit_code__ = None;
                let mut stdout_raw__ = None;
                let mut stdout_digest__ = None;
                let mut stderr_raw__ = None;
                let mut stderr_digest__ = None;
                let mut execution_metadata__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::OutputFiles => {
                            if output_files__.is_some() {
                                return Err(serde::de::Error::duplicate_field("outputFiles"));
                            }
                            output_files__ = Some(map_.next_value()?);
                        }
                        GeneratedField::OutputFileSymlinks => {
                            if output_file_symlinks__.is_some() {
                                return Err(serde::de::Error::duplicate_field("outputFileSymlinks"));
                            }
                            output_file_symlinks__ = Some(map_.next_value()?);
                        }
                        GeneratedField::OutputSymlinks => {
                            if output_symlinks__.is_some() {
                                return Err(serde::de::Error::duplicate_field("outputSymlinks"));
                            }
                            output_symlinks__ = Some(map_.next_value()?);
                        }
                        GeneratedField::OutputDirectories => {
                            if output_directories__.is_some() {
                                return Err(serde::de::Error::duplicate_field("outputDirectories"));
                            }
                            output_directories__ = Some(map_.next_value()?);
                        }
                        GeneratedField::OutputDirectorySymlinks => {
                            if output_directory_symlinks__.is_some() {
                                return Err(serde::de::Error::duplicate_field("outputDirectorySymlinks"));
                            }
                            output_directory_symlinks__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ExitCode => {
                            if exit_code__.is_some() {
                                return Err(serde::de::Error::duplicate_field("exitCode"));
                            }
                            exit_code__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::StdoutRaw => {
                            if stdout_raw__.is_some() {
                                return Err(serde::de::Error::duplicate_field("stdoutRaw"));
                            }
                            stdout_raw__ = 
                                Some(map_.next_value::<::pbjson::private::BytesDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::StdoutDigest => {
                            if stdout_digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("stdoutDigest"));
                            }
                            stdout_digest__ = map_.next_value()?;
                        }
                        GeneratedField::StderrRaw => {
                            if stderr_raw__.is_some() {
                                return Err(serde::de::Error::duplicate_field("stderrRaw"));
                            }
                            stderr_raw__ = 
                                Some(map_.next_value::<::pbjson::private::BytesDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::StderrDigest => {
                            if stderr_digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("stderrDigest"));
                            }
                            stderr_digest__ = map_.next_value()?;
                        }
                        GeneratedField::ExecutionMetadata => {
                            if execution_metadata__.is_some() {
                                return Err(serde::de::Error::duplicate_field("executionMetadata"));
                            }
                            execution_metadata__ = map_.next_value()?;
                        }
                    }
                }
                Ok(ActionResult {
                    output_files: output_files__.unwrap_or_default(),
                    output_file_symlinks: output_file_symlinks__.unwrap_or_default(),
                    output_symlinks: output_symlinks__.unwrap_or_default(),
                    output_directories: output_directories__.unwrap_or_default(),
                    output_directory_symlinks: output_directory_symlinks__.unwrap_or_default(),
                    exit_code: exit_code__.unwrap_or_default(),
                    stdout_raw: stdout_raw__.unwrap_or_default(),
                    stdout_digest: stdout_digest__,
                    stderr_raw: stderr_raw__.unwrap_or_default(),
                    stderr_digest: stderr_digest__,
                    execution_metadata: execution_metadata__,
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.ActionResult", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for BatchReadBlobsRequest {
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
        if !self.digests.is_empty() {
            len += 1;
        }
        if !self.acceptable_compressors.is_empty() {
            len += 1;
        }
        if self.digest_function != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.BatchReadBlobsRequest", len)?;
        if !self.instance_name.is_empty() {
            struct_ser.serialize_field("instanceName", &self.instance_name)?;
        }
        if !self.digests.is_empty() {
            struct_ser.serialize_field("digests", &self.digests)?;
        }
        if !self.acceptable_compressors.is_empty() {
            let v = self.acceptable_compressors.iter().cloned().map(|v| {
                compressor::Value::try_from(v)
                    .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", v)))
                }).collect::<std::result::Result<Vec<_>, _>>()?;
            struct_ser.serialize_field("acceptableCompressors", &v)?;
        }
        if self.digest_function != 0 {
            let v = digest_function::Value::try_from(self.digest_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.digest_function)))?;
            struct_ser.serialize_field("digestFunction", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for BatchReadBlobsRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "instance_name",
            "instanceName",
            "digests",
            "acceptable_compressors",
            "acceptableCompressors",
            "digest_function",
            "digestFunction",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            InstanceName,
            Digests,
            AcceptableCompressors,
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
                            "digests" => Ok(GeneratedField::Digests),
                            "acceptableCompressors" | "acceptable_compressors" => Ok(GeneratedField::AcceptableCompressors),
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
            type Value = BatchReadBlobsRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.BatchReadBlobsRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<BatchReadBlobsRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut instance_name__ = None;
                let mut digests__ = None;
                let mut acceptable_compressors__ = None;
                let mut digest_function__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::InstanceName => {
                            if instance_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("instanceName"));
                            }
                            instance_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Digests => {
                            if digests__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digests"));
                            }
                            digests__ = Some(map_.next_value()?);
                        }
                        GeneratedField::AcceptableCompressors => {
                            if acceptable_compressors__.is_some() {
                                return Err(serde::de::Error::duplicate_field("acceptableCompressors"));
                            }
                            acceptable_compressors__ = Some(map_.next_value::<Vec<compressor::Value>>()?.into_iter().map(|x| x as i32).collect());
                        }
                        GeneratedField::DigestFunction => {
                            if digest_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digestFunction"));
                            }
                            digest_function__ = Some(map_.next_value::<digest_function::Value>()? as i32);
                        }
                    }
                }
                Ok(BatchReadBlobsRequest {
                    instance_name: instance_name__.unwrap_or_default(),
                    digests: digests__.unwrap_or_default(),
                    acceptable_compressors: acceptable_compressors__.unwrap_or_default(),
                    digest_function: digest_function__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.BatchReadBlobsRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for BatchReadBlobsResponse {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.responses.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.BatchReadBlobsResponse", len)?;
        if !self.responses.is_empty() {
            struct_ser.serialize_field("responses", &self.responses)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for BatchReadBlobsResponse {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "responses",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Responses,
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
                            "responses" => Ok(GeneratedField::Responses),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = BatchReadBlobsResponse;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.BatchReadBlobsResponse")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<BatchReadBlobsResponse, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut responses__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Responses => {
                            if responses__.is_some() {
                                return Err(serde::de::Error::duplicate_field("responses"));
                            }
                            responses__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(BatchReadBlobsResponse {
                    responses: responses__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.BatchReadBlobsResponse", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for batch_read_blobs_response::Response {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.digest.is_some() {
            len += 1;
        }
        if !self.data.is_empty() {
            len += 1;
        }
        if self.compressor != 0 {
            len += 1;
        }
        if self.status.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.BatchReadBlobsResponse.Response", len)?;
        if let Some(v) = self.digest.as_ref() {
            struct_ser.serialize_field("digest", v)?;
        }
        if !self.data.is_empty() {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("data", pbjson::private::base64::encode(&self.data).as_str())?;
        }
        if self.compressor != 0 {
            let v = compressor::Value::try_from(self.compressor)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.compressor)))?;
            struct_ser.serialize_field("compressor", &v)?;
        }
        if let Some(v) = self.status.as_ref() {
            struct_ser.serialize_field("status", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for batch_read_blobs_response::Response {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "digest",
            "data",
            "compressor",
            "status",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Digest,
            Data,
            Compressor,
            Status,
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
                            "digest" => Ok(GeneratedField::Digest),
                            "data" => Ok(GeneratedField::Data),
                            "compressor" => Ok(GeneratedField::Compressor),
                            "status" => Ok(GeneratedField::Status),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = batch_read_blobs_response::Response;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.BatchReadBlobsResponse.Response")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<batch_read_blobs_response::Response, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut digest__ = None;
                let mut data__ = None;
                let mut compressor__ = None;
                let mut status__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Digest => {
                            if digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digest"));
                            }
                            digest__ = map_.next_value()?;
                        }
                        GeneratedField::Data => {
                            if data__.is_some() {
                                return Err(serde::de::Error::duplicate_field("data"));
                            }
                            data__ = 
                                Some(map_.next_value::<::pbjson::private::BytesDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Compressor => {
                            if compressor__.is_some() {
                                return Err(serde::de::Error::duplicate_field("compressor"));
                            }
                            compressor__ = Some(map_.next_value::<compressor::Value>()? as i32);
                        }
                        GeneratedField::Status => {
                            if status__.is_some() {
                                return Err(serde::de::Error::duplicate_field("status"));
                            }
                            status__ = map_.next_value()?;
                        }
                    }
                }
                Ok(batch_read_blobs_response::Response {
                    digest: digest__,
                    data: data__.unwrap_or_default(),
                    compressor: compressor__.unwrap_or_default(),
                    status: status__,
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.BatchReadBlobsResponse.Response", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for BatchUpdateBlobsRequest {
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
        if !self.requests.is_empty() {
            len += 1;
        }
        if self.digest_function != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.BatchUpdateBlobsRequest", len)?;
        if !self.instance_name.is_empty() {
            struct_ser.serialize_field("instanceName", &self.instance_name)?;
        }
        if !self.requests.is_empty() {
            struct_ser.serialize_field("requests", &self.requests)?;
        }
        if self.digest_function != 0 {
            let v = digest_function::Value::try_from(self.digest_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.digest_function)))?;
            struct_ser.serialize_field("digestFunction", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for BatchUpdateBlobsRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "instance_name",
            "instanceName",
            "requests",
            "digest_function",
            "digestFunction",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            InstanceName,
            Requests,
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
                            "requests" => Ok(GeneratedField::Requests),
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
            type Value = BatchUpdateBlobsRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.BatchUpdateBlobsRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<BatchUpdateBlobsRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut instance_name__ = None;
                let mut requests__ = None;
                let mut digest_function__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::InstanceName => {
                            if instance_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("instanceName"));
                            }
                            instance_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Requests => {
                            if requests__.is_some() {
                                return Err(serde::de::Error::duplicate_field("requests"));
                            }
                            requests__ = Some(map_.next_value()?);
                        }
                        GeneratedField::DigestFunction => {
                            if digest_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digestFunction"));
                            }
                            digest_function__ = Some(map_.next_value::<digest_function::Value>()? as i32);
                        }
                    }
                }
                Ok(BatchUpdateBlobsRequest {
                    instance_name: instance_name__.unwrap_or_default(),
                    requests: requests__.unwrap_or_default(),
                    digest_function: digest_function__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.BatchUpdateBlobsRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for batch_update_blobs_request::Request {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.digest.is_some() {
            len += 1;
        }
        if !self.data.is_empty() {
            len += 1;
        }
        if self.compressor != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.BatchUpdateBlobsRequest.Request", len)?;
        if let Some(v) = self.digest.as_ref() {
            struct_ser.serialize_field("digest", v)?;
        }
        if !self.data.is_empty() {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("data", pbjson::private::base64::encode(&self.data).as_str())?;
        }
        if self.compressor != 0 {
            let v = compressor::Value::try_from(self.compressor)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.compressor)))?;
            struct_ser.serialize_field("compressor", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for batch_update_blobs_request::Request {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "digest",
            "data",
            "compressor",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Digest,
            Data,
            Compressor,
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
                            "digest" => Ok(GeneratedField::Digest),
                            "data" => Ok(GeneratedField::Data),
                            "compressor" => Ok(GeneratedField::Compressor),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = batch_update_blobs_request::Request;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.BatchUpdateBlobsRequest.Request")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<batch_update_blobs_request::Request, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut digest__ = None;
                let mut data__ = None;
                let mut compressor__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Digest => {
                            if digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digest"));
                            }
                            digest__ = map_.next_value()?;
                        }
                        GeneratedField::Data => {
                            if data__.is_some() {
                                return Err(serde::de::Error::duplicate_field("data"));
                            }
                            data__ = 
                                Some(map_.next_value::<::pbjson::private::BytesDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Compressor => {
                            if compressor__.is_some() {
                                return Err(serde::de::Error::duplicate_field("compressor"));
                            }
                            compressor__ = Some(map_.next_value::<compressor::Value>()? as i32);
                        }
                    }
                }
                Ok(batch_update_blobs_request::Request {
                    digest: digest__,
                    data: data__.unwrap_or_default(),
                    compressor: compressor__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.BatchUpdateBlobsRequest.Request", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for BatchUpdateBlobsResponse {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.responses.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.BatchUpdateBlobsResponse", len)?;
        if !self.responses.is_empty() {
            struct_ser.serialize_field("responses", &self.responses)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for BatchUpdateBlobsResponse {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "responses",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Responses,
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
                            "responses" => Ok(GeneratedField::Responses),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = BatchUpdateBlobsResponse;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.BatchUpdateBlobsResponse")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<BatchUpdateBlobsResponse, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut responses__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Responses => {
                            if responses__.is_some() {
                                return Err(serde::de::Error::duplicate_field("responses"));
                            }
                            responses__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(BatchUpdateBlobsResponse {
                    responses: responses__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.BatchUpdateBlobsResponse", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for batch_update_blobs_response::Response {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.digest.is_some() {
            len += 1;
        }
        if self.status.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.BatchUpdateBlobsResponse.Response", len)?;
        if let Some(v) = self.digest.as_ref() {
            struct_ser.serialize_field("digest", v)?;
        }
        if let Some(v) = self.status.as_ref() {
            struct_ser.serialize_field("status", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for batch_update_blobs_response::Response {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "digest",
            "status",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Digest,
            Status,
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
                            "digest" => Ok(GeneratedField::Digest),
                            "status" => Ok(GeneratedField::Status),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = batch_update_blobs_response::Response;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.BatchUpdateBlobsResponse.Response")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<batch_update_blobs_response::Response, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut digest__ = None;
                let mut status__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Digest => {
                            if digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digest"));
                            }
                            digest__ = map_.next_value()?;
                        }
                        GeneratedField::Status => {
                            if status__.is_some() {
                                return Err(serde::de::Error::duplicate_field("status"));
                            }
                            status__ = map_.next_value()?;
                        }
                    }
                }
                Ok(batch_update_blobs_response::Response {
                    digest: digest__,
                    status: status__,
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.BatchUpdateBlobsResponse.Response", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for CacheCapabilities {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.digest_functions.is_empty() {
            len += 1;
        }
        if self.action_cache_update_capabilities.is_some() {
            len += 1;
        }
        if self.cache_priority_capabilities.is_some() {
            len += 1;
        }
        if self.max_batch_total_size_bytes != 0 {
            len += 1;
        }
        if self.symlink_absolute_path_strategy != 0 {
            len += 1;
        }
        if !self.supported_compressors.is_empty() {
            len += 1;
        }
        if !self.supported_batch_update_compressors.is_empty() {
            len += 1;
        }
        if self.max_cas_blob_size_bytes != 0 {
            len += 1;
        }
        if self.split_blob_support {
            len += 1;
        }
        if self.splice_blob_support {
            len += 1;
        }
        if self.fast_cdc_2020_params.is_some() {
            len += 1;
        }
        if self.rep_max_cdc_params.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.CacheCapabilities", len)?;
        if !self.digest_functions.is_empty() {
            let v = self.digest_functions.iter().cloned().map(|v| {
                digest_function::Value::try_from(v)
                    .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", v)))
                }).collect::<std::result::Result<Vec<_>, _>>()?;
            struct_ser.serialize_field("digestFunctions", &v)?;
        }
        if let Some(v) = self.action_cache_update_capabilities.as_ref() {
            struct_ser.serialize_field("actionCacheUpdateCapabilities", v)?;
        }
        if let Some(v) = self.cache_priority_capabilities.as_ref() {
            struct_ser.serialize_field("cachePriorityCapabilities", v)?;
        }
        if self.max_batch_total_size_bytes != 0 {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("maxBatchTotalSizeBytes", ToString::to_string(&self.max_batch_total_size_bytes).as_str())?;
        }
        if self.symlink_absolute_path_strategy != 0 {
            let v = symlink_absolute_path_strategy::Value::try_from(self.symlink_absolute_path_strategy)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.symlink_absolute_path_strategy)))?;
            struct_ser.serialize_field("symlinkAbsolutePathStrategy", &v)?;
        }
        if !self.supported_compressors.is_empty() {
            let v = self.supported_compressors.iter().cloned().map(|v| {
                compressor::Value::try_from(v)
                    .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", v)))
                }).collect::<std::result::Result<Vec<_>, _>>()?;
            struct_ser.serialize_field("supportedCompressors", &v)?;
        }
        if !self.supported_batch_update_compressors.is_empty() {
            let v = self.supported_batch_update_compressors.iter().cloned().map(|v| {
                compressor::Value::try_from(v)
                    .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", v)))
                }).collect::<std::result::Result<Vec<_>, _>>()?;
            struct_ser.serialize_field("supportedBatchUpdateCompressors", &v)?;
        }
        if self.max_cas_blob_size_bytes != 0 {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("maxCasBlobSizeBytes", ToString::to_string(&self.max_cas_blob_size_bytes).as_str())?;
        }
        if self.split_blob_support {
            struct_ser.serialize_field("splitBlobSupport", &self.split_blob_support)?;
        }
        if self.splice_blob_support {
            struct_ser.serialize_field("spliceBlobSupport", &self.splice_blob_support)?;
        }
        if let Some(v) = self.fast_cdc_2020_params.as_ref() {
            struct_ser.serialize_field("fastCdc2020Params", v)?;
        }
        if let Some(v) = self.rep_max_cdc_params.as_ref() {
            struct_ser.serialize_field("repMaxCdcParams", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for CacheCapabilities {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "digest_functions",
            "digestFunctions",
            "action_cache_update_capabilities",
            "actionCacheUpdateCapabilities",
            "cache_priority_capabilities",
            "cachePriorityCapabilities",
            "max_batch_total_size_bytes",
            "maxBatchTotalSizeBytes",
            "symlink_absolute_path_strategy",
            "symlinkAbsolutePathStrategy",
            "supported_compressors",
            "supportedCompressors",
            "supported_batch_update_compressors",
            "supportedBatchUpdateCompressors",
            "max_cas_blob_size_bytes",
            "maxCasBlobSizeBytes",
            "split_blob_support",
            "splitBlobSupport",
            "splice_blob_support",
            "spliceBlobSupport",
            "fast_cdc_2020_params",
            "fastCdc2020Params",
            "rep_max_cdc_params",
            "repMaxCdcParams",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            DigestFunctions,
            ActionCacheUpdateCapabilities,
            CachePriorityCapabilities,
            MaxBatchTotalSizeBytes,
            SymlinkAbsolutePathStrategy,
            SupportedCompressors,
            SupportedBatchUpdateCompressors,
            MaxCasBlobSizeBytes,
            SplitBlobSupport,
            SpliceBlobSupport,
            FastCdc2020Params,
            RepMaxCdcParams,
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
                            "digestFunctions" | "digest_functions" => Ok(GeneratedField::DigestFunctions),
                            "actionCacheUpdateCapabilities" | "action_cache_update_capabilities" => Ok(GeneratedField::ActionCacheUpdateCapabilities),
                            "cachePriorityCapabilities" | "cache_priority_capabilities" => Ok(GeneratedField::CachePriorityCapabilities),
                            "maxBatchTotalSizeBytes" | "max_batch_total_size_bytes" => Ok(GeneratedField::MaxBatchTotalSizeBytes),
                            "symlinkAbsolutePathStrategy" | "symlink_absolute_path_strategy" => Ok(GeneratedField::SymlinkAbsolutePathStrategy),
                            "supportedCompressors" | "supported_compressors" => Ok(GeneratedField::SupportedCompressors),
                            "supportedBatchUpdateCompressors" | "supported_batch_update_compressors" => Ok(GeneratedField::SupportedBatchUpdateCompressors),
                            "maxCasBlobSizeBytes" | "max_cas_blob_size_bytes" => Ok(GeneratedField::MaxCasBlobSizeBytes),
                            "splitBlobSupport" | "split_blob_support" => Ok(GeneratedField::SplitBlobSupport),
                            "spliceBlobSupport" | "splice_blob_support" => Ok(GeneratedField::SpliceBlobSupport),
                            "fastCdc2020Params" | "fast_cdc_2020_params" => Ok(GeneratedField::FastCdc2020Params),
                            "repMaxCdcParams" | "rep_max_cdc_params" => Ok(GeneratedField::RepMaxCdcParams),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = CacheCapabilities;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.CacheCapabilities")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<CacheCapabilities, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut digest_functions__ = None;
                let mut action_cache_update_capabilities__ = None;
                let mut cache_priority_capabilities__ = None;
                let mut max_batch_total_size_bytes__ = None;
                let mut symlink_absolute_path_strategy__ = None;
                let mut supported_compressors__ = None;
                let mut supported_batch_update_compressors__ = None;
                let mut max_cas_blob_size_bytes__ = None;
                let mut split_blob_support__ = None;
                let mut splice_blob_support__ = None;
                let mut fast_cdc_2020_params__ = None;
                let mut rep_max_cdc_params__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::DigestFunctions => {
                            if digest_functions__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digestFunctions"));
                            }
                            digest_functions__ = Some(map_.next_value::<Vec<digest_function::Value>>()?.into_iter().map(|x| x as i32).collect());
                        }
                        GeneratedField::ActionCacheUpdateCapabilities => {
                            if action_cache_update_capabilities__.is_some() {
                                return Err(serde::de::Error::duplicate_field("actionCacheUpdateCapabilities"));
                            }
                            action_cache_update_capabilities__ = map_.next_value()?;
                        }
                        GeneratedField::CachePriorityCapabilities => {
                            if cache_priority_capabilities__.is_some() {
                                return Err(serde::de::Error::duplicate_field("cachePriorityCapabilities"));
                            }
                            cache_priority_capabilities__ = map_.next_value()?;
                        }
                        GeneratedField::MaxBatchTotalSizeBytes => {
                            if max_batch_total_size_bytes__.is_some() {
                                return Err(serde::de::Error::duplicate_field("maxBatchTotalSizeBytes"));
                            }
                            max_batch_total_size_bytes__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::SymlinkAbsolutePathStrategy => {
                            if symlink_absolute_path_strategy__.is_some() {
                                return Err(serde::de::Error::duplicate_field("symlinkAbsolutePathStrategy"));
                            }
                            symlink_absolute_path_strategy__ = Some(map_.next_value::<symlink_absolute_path_strategy::Value>()? as i32);
                        }
                        GeneratedField::SupportedCompressors => {
                            if supported_compressors__.is_some() {
                                return Err(serde::de::Error::duplicate_field("supportedCompressors"));
                            }
                            supported_compressors__ = Some(map_.next_value::<Vec<compressor::Value>>()?.into_iter().map(|x| x as i32).collect());
                        }
                        GeneratedField::SupportedBatchUpdateCompressors => {
                            if supported_batch_update_compressors__.is_some() {
                                return Err(serde::de::Error::duplicate_field("supportedBatchUpdateCompressors"));
                            }
                            supported_batch_update_compressors__ = Some(map_.next_value::<Vec<compressor::Value>>()?.into_iter().map(|x| x as i32).collect());
                        }
                        GeneratedField::MaxCasBlobSizeBytes => {
                            if max_cas_blob_size_bytes__.is_some() {
                                return Err(serde::de::Error::duplicate_field("maxCasBlobSizeBytes"));
                            }
                            max_cas_blob_size_bytes__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::SplitBlobSupport => {
                            if split_blob_support__.is_some() {
                                return Err(serde::de::Error::duplicate_field("splitBlobSupport"));
                            }
                            split_blob_support__ = Some(map_.next_value()?);
                        }
                        GeneratedField::SpliceBlobSupport => {
                            if splice_blob_support__.is_some() {
                                return Err(serde::de::Error::duplicate_field("spliceBlobSupport"));
                            }
                            splice_blob_support__ = Some(map_.next_value()?);
                        }
                        GeneratedField::FastCdc2020Params => {
                            if fast_cdc_2020_params__.is_some() {
                                return Err(serde::de::Error::duplicate_field("fastCdc2020Params"));
                            }
                            fast_cdc_2020_params__ = map_.next_value()?;
                        }
                        GeneratedField::RepMaxCdcParams => {
                            if rep_max_cdc_params__.is_some() {
                                return Err(serde::de::Error::duplicate_field("repMaxCdcParams"));
                            }
                            rep_max_cdc_params__ = map_.next_value()?;
                        }
                    }
                }
                Ok(CacheCapabilities {
                    digest_functions: digest_functions__.unwrap_or_default(),
                    action_cache_update_capabilities: action_cache_update_capabilities__,
                    cache_priority_capabilities: cache_priority_capabilities__,
                    max_batch_total_size_bytes: max_batch_total_size_bytes__.unwrap_or_default(),
                    symlink_absolute_path_strategy: symlink_absolute_path_strategy__.unwrap_or_default(),
                    supported_compressors: supported_compressors__.unwrap_or_default(),
                    supported_batch_update_compressors: supported_batch_update_compressors__.unwrap_or_default(),
                    max_cas_blob_size_bytes: max_cas_blob_size_bytes__.unwrap_or_default(),
                    split_blob_support: split_blob_support__.unwrap_or_default(),
                    splice_blob_support: splice_blob_support__.unwrap_or_default(),
                    fast_cdc_2020_params: fast_cdc_2020_params__,
                    rep_max_cdc_params: rep_max_cdc_params__,
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.CacheCapabilities", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ChunkingFunction {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let len = 0;
        let struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.ChunkingFunction", len)?;
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ChunkingFunction {
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
            type Value = ChunkingFunction;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.ChunkingFunction")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ChunkingFunction, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                while map_.next_key::<GeneratedField>()?.is_some() {
                    let _ = map_.next_value::<serde::de::IgnoredAny>()?;
                }
                Ok(ChunkingFunction {
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.ChunkingFunction", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for chunking_function::Value {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let variant = match self {
            Self::Unknown => "UNKNOWN",
            Self::FastCdc2020 => "FAST_CDC_2020",
            Self::RepMaxCdc => "REP_MAX_CDC",
        };
        serializer.serialize_str(variant)
    }
}
impl<'de> serde::Deserialize<'de> for chunking_function::Value {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "UNKNOWN",
            "FAST_CDC_2020",
            "REP_MAX_CDC",
        ];

        struct GeneratedVisitor;

        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = chunking_function::Value;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                write!(formatter, "expected one of: {:?}", &FIELDS)
            }

            fn visit_i64<E>(self, v: i64) -> std::result::Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                i32::try_from(v)
                    .ok()
                    .and_then(|x| x.try_into().ok())
                    .ok_or_else(|| {
                        serde::de::Error::invalid_value(serde::de::Unexpected::Signed(v), &self)
                    })
            }

            fn visit_u64<E>(self, v: u64) -> std::result::Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                i32::try_from(v)
                    .ok()
                    .and_then(|x| x.try_into().ok())
                    .ok_or_else(|| {
                        serde::de::Error::invalid_value(serde::de::Unexpected::Unsigned(v), &self)
                    })
            }

            fn visit_str<E>(self, value: &str) -> std::result::Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                match value {
                    "UNKNOWN" => Ok(chunking_function::Value::Unknown),
                    "FAST_CDC_2020" => Ok(chunking_function::Value::FastCdc2020),
                    "REP_MAX_CDC" => Ok(chunking_function::Value::RepMaxCdc),
                    _ => Err(serde::de::Error::unknown_variant(value, FIELDS)),
                }
            }
        }
        deserializer.deserialize_any(GeneratedVisitor)
    }
}
impl serde::Serialize for Command {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.arguments.is_empty() {
            len += 1;
        }
        if !self.environment_variables.is_empty() {
            len += 1;
        }
        if !self.output_files.is_empty() {
            len += 1;
        }
        if !self.output_directories.is_empty() {
            len += 1;
        }
        if !self.output_paths.is_empty() {
            len += 1;
        }
        if self.platform.is_some() {
            len += 1;
        }
        if !self.working_directory.is_empty() {
            len += 1;
        }
        if !self.output_node_properties.is_empty() {
            len += 1;
        }
        if self.output_directory_format != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.Command", len)?;
        if !self.arguments.is_empty() {
            struct_ser.serialize_field("arguments", &self.arguments)?;
        }
        if !self.environment_variables.is_empty() {
            struct_ser.serialize_field("environmentVariables", &self.environment_variables)?;
        }
        if !self.output_files.is_empty() {
            struct_ser.serialize_field("outputFiles", &self.output_files)?;
        }
        if !self.output_directories.is_empty() {
            struct_ser.serialize_field("outputDirectories", &self.output_directories)?;
        }
        if !self.output_paths.is_empty() {
            struct_ser.serialize_field("outputPaths", &self.output_paths)?;
        }
        if let Some(v) = self.platform.as_ref() {
            struct_ser.serialize_field("platform", v)?;
        }
        if !self.working_directory.is_empty() {
            struct_ser.serialize_field("workingDirectory", &self.working_directory)?;
        }
        if !self.output_node_properties.is_empty() {
            struct_ser.serialize_field("outputNodeProperties", &self.output_node_properties)?;
        }
        if self.output_directory_format != 0 {
            let v = command::OutputDirectoryFormat::try_from(self.output_directory_format)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.output_directory_format)))?;
            struct_ser.serialize_field("outputDirectoryFormat", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for Command {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "arguments",
            "environment_variables",
            "environmentVariables",
            "output_files",
            "outputFiles",
            "output_directories",
            "outputDirectories",
            "output_paths",
            "outputPaths",
            "platform",
            "working_directory",
            "workingDirectory",
            "output_node_properties",
            "outputNodeProperties",
            "output_directory_format",
            "outputDirectoryFormat",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Arguments,
            EnvironmentVariables,
            OutputFiles,
            OutputDirectories,
            OutputPaths,
            Platform,
            WorkingDirectory,
            OutputNodeProperties,
            OutputDirectoryFormat,
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
                            "arguments" => Ok(GeneratedField::Arguments),
                            "environmentVariables" | "environment_variables" => Ok(GeneratedField::EnvironmentVariables),
                            "outputFiles" | "output_files" => Ok(GeneratedField::OutputFiles),
                            "outputDirectories" | "output_directories" => Ok(GeneratedField::OutputDirectories),
                            "outputPaths" | "output_paths" => Ok(GeneratedField::OutputPaths),
                            "platform" => Ok(GeneratedField::Platform),
                            "workingDirectory" | "working_directory" => Ok(GeneratedField::WorkingDirectory),
                            "outputNodeProperties" | "output_node_properties" => Ok(GeneratedField::OutputNodeProperties),
                            "outputDirectoryFormat" | "output_directory_format" => Ok(GeneratedField::OutputDirectoryFormat),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = Command;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.Command")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<Command, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut arguments__ = None;
                let mut environment_variables__ = None;
                let mut output_files__ = None;
                let mut output_directories__ = None;
                let mut output_paths__ = None;
                let mut platform__ = None;
                let mut working_directory__ = None;
                let mut output_node_properties__ = None;
                let mut output_directory_format__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Arguments => {
                            if arguments__.is_some() {
                                return Err(serde::de::Error::duplicate_field("arguments"));
                            }
                            arguments__ = Some(map_.next_value()?);
                        }
                        GeneratedField::EnvironmentVariables => {
                            if environment_variables__.is_some() {
                                return Err(serde::de::Error::duplicate_field("environmentVariables"));
                            }
                            environment_variables__ = Some(map_.next_value()?);
                        }
                        GeneratedField::OutputFiles => {
                            if output_files__.is_some() {
                                return Err(serde::de::Error::duplicate_field("outputFiles"));
                            }
                            output_files__ = Some(map_.next_value()?);
                        }
                        GeneratedField::OutputDirectories => {
                            if output_directories__.is_some() {
                                return Err(serde::de::Error::duplicate_field("outputDirectories"));
                            }
                            output_directories__ = Some(map_.next_value()?);
                        }
                        GeneratedField::OutputPaths => {
                            if output_paths__.is_some() {
                                return Err(serde::de::Error::duplicate_field("outputPaths"));
                            }
                            output_paths__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Platform => {
                            if platform__.is_some() {
                                return Err(serde::de::Error::duplicate_field("platform"));
                            }
                            platform__ = map_.next_value()?;
                        }
                        GeneratedField::WorkingDirectory => {
                            if working_directory__.is_some() {
                                return Err(serde::de::Error::duplicate_field("workingDirectory"));
                            }
                            working_directory__ = Some(map_.next_value()?);
                        }
                        GeneratedField::OutputNodeProperties => {
                            if output_node_properties__.is_some() {
                                return Err(serde::de::Error::duplicate_field("outputNodeProperties"));
                            }
                            output_node_properties__ = Some(map_.next_value()?);
                        }
                        GeneratedField::OutputDirectoryFormat => {
                            if output_directory_format__.is_some() {
                                return Err(serde::de::Error::duplicate_field("outputDirectoryFormat"));
                            }
                            output_directory_format__ = Some(map_.next_value::<command::OutputDirectoryFormat>()? as i32);
                        }
                    }
                }
                Ok(Command {
                    arguments: arguments__.unwrap_or_default(),
                    environment_variables: environment_variables__.unwrap_or_default(),
                    output_files: output_files__.unwrap_or_default(),
                    output_directories: output_directories__.unwrap_or_default(),
                    output_paths: output_paths__.unwrap_or_default(),
                    platform: platform__,
                    working_directory: working_directory__.unwrap_or_default(),
                    output_node_properties: output_node_properties__.unwrap_or_default(),
                    output_directory_format: output_directory_format__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.Command", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for command::EnvironmentVariable {
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
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.Command.EnvironmentVariable", len)?;
        if !self.name.is_empty() {
            struct_ser.serialize_field("name", &self.name)?;
        }
        if !self.value.is_empty() {
            struct_ser.serialize_field("value", &self.value)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for command::EnvironmentVariable {
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
            type Value = command::EnvironmentVariable;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.Command.EnvironmentVariable")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<command::EnvironmentVariable, V::Error>
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
                Ok(command::EnvironmentVariable {
                    name: name__.unwrap_or_default(),
                    value: value__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.Command.EnvironmentVariable", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for command::OutputDirectoryFormat {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let variant = match self {
            Self::TreeOnly => "TREE_ONLY",
            Self::DirectoryOnly => "DIRECTORY_ONLY",
            Self::TreeAndDirectory => "TREE_AND_DIRECTORY",
        };
        serializer.serialize_str(variant)
    }
}
impl<'de> serde::Deserialize<'de> for command::OutputDirectoryFormat {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "TREE_ONLY",
            "DIRECTORY_ONLY",
            "TREE_AND_DIRECTORY",
        ];

        struct GeneratedVisitor;

        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = command::OutputDirectoryFormat;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                write!(formatter, "expected one of: {:?}", &FIELDS)
            }

            fn visit_i64<E>(self, v: i64) -> std::result::Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                i32::try_from(v)
                    .ok()
                    .and_then(|x| x.try_into().ok())
                    .ok_or_else(|| {
                        serde::de::Error::invalid_value(serde::de::Unexpected::Signed(v), &self)
                    })
            }

            fn visit_u64<E>(self, v: u64) -> std::result::Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                i32::try_from(v)
                    .ok()
                    .and_then(|x| x.try_into().ok())
                    .ok_or_else(|| {
                        serde::de::Error::invalid_value(serde::de::Unexpected::Unsigned(v), &self)
                    })
            }

            fn visit_str<E>(self, value: &str) -> std::result::Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                match value {
                    "TREE_ONLY" => Ok(command::OutputDirectoryFormat::TreeOnly),
                    "DIRECTORY_ONLY" => Ok(command::OutputDirectoryFormat::DirectoryOnly),
                    "TREE_AND_DIRECTORY" => Ok(command::OutputDirectoryFormat::TreeAndDirectory),
                    _ => Err(serde::de::Error::unknown_variant(value, FIELDS)),
                }
            }
        }
        deserializer.deserialize_any(GeneratedVisitor)
    }
}
impl serde::Serialize for Compressor {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let len = 0;
        let struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.Compressor", len)?;
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for Compressor {
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
            type Value = Compressor;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.Compressor")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<Compressor, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                while map_.next_key::<GeneratedField>()?.is_some() {
                    let _ = map_.next_value::<serde::de::IgnoredAny>()?;
                }
                Ok(Compressor {
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.Compressor", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for compressor::Value {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let variant = match self {
            Self::Identity => "IDENTITY",
            Self::Zstd => "ZSTD",
            Self::Deflate => "DEFLATE",
            Self::Brotli => "BROTLI",
        };
        serializer.serialize_str(variant)
    }
}
impl<'de> serde::Deserialize<'de> for compressor::Value {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "IDENTITY",
            "ZSTD",
            "DEFLATE",
            "BROTLI",
        ];

        struct GeneratedVisitor;

        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = compressor::Value;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                write!(formatter, "expected one of: {:?}", &FIELDS)
            }

            fn visit_i64<E>(self, v: i64) -> std::result::Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                i32::try_from(v)
                    .ok()
                    .and_then(|x| x.try_into().ok())
                    .ok_or_else(|| {
                        serde::de::Error::invalid_value(serde::de::Unexpected::Signed(v), &self)
                    })
            }

            fn visit_u64<E>(self, v: u64) -> std::result::Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                i32::try_from(v)
                    .ok()
                    .and_then(|x| x.try_into().ok())
                    .ok_or_else(|| {
                        serde::de::Error::invalid_value(serde::de::Unexpected::Unsigned(v), &self)
                    })
            }

            fn visit_str<E>(self, value: &str) -> std::result::Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                match value {
                    "IDENTITY" => Ok(compressor::Value::Identity),
                    "ZSTD" => Ok(compressor::Value::Zstd),
                    "DEFLATE" => Ok(compressor::Value::Deflate),
                    "BROTLI" => Ok(compressor::Value::Brotli),
                    _ => Err(serde::de::Error::unknown_variant(value, FIELDS)),
                }
            }
        }
        deserializer.deserialize_any(GeneratedVisitor)
    }
}
impl serde::Serialize for Digest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.hash.is_empty() {
            len += 1;
        }
        if self.size_bytes != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.Digest", len)?;
        if !self.hash.is_empty() {
            struct_ser.serialize_field("hash", &self.hash)?;
        }
        if self.size_bytes != 0 {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("sizeBytes", ToString::to_string(&self.size_bytes).as_str())?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for Digest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "hash",
            "size_bytes",
            "sizeBytes",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Hash,
            SizeBytes,
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
                            "hash" => Ok(GeneratedField::Hash),
                            "sizeBytes" | "size_bytes" => Ok(GeneratedField::SizeBytes),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = Digest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.Digest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<Digest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut hash__ = None;
                let mut size_bytes__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Hash => {
                            if hash__.is_some() {
                                return Err(serde::de::Error::duplicate_field("hash"));
                            }
                            hash__ = Some(map_.next_value()?);
                        }
                        GeneratedField::SizeBytes => {
                            if size_bytes__.is_some() {
                                return Err(serde::de::Error::duplicate_field("sizeBytes"));
                            }
                            size_bytes__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                    }
                }
                Ok(Digest {
                    hash: hash__.unwrap_or_default(),
                    size_bytes: size_bytes__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.Digest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for DigestFunction {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let len = 0;
        let struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.DigestFunction", len)?;
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for DigestFunction {
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
            type Value = DigestFunction;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.DigestFunction")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<DigestFunction, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                while map_.next_key::<GeneratedField>()?.is_some() {
                    let _ = map_.next_value::<serde::de::IgnoredAny>()?;
                }
                Ok(DigestFunction {
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.DigestFunction", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for digest_function::Value {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let variant = match self {
            Self::Unknown => "UNKNOWN",
            Self::Sha256 => "SHA256",
            Self::Sha1 => "SHA1",
            Self::Md5 => "MD5",
            Self::Vso => "VSO",
            Self::Sha384 => "SHA384",
            Self::Sha512 => "SHA512",
            Self::Murmur3 => "MURMUR3",
            Self::Sha256tree => "SHA256TREE",
            Self::Blake3 => "BLAKE3",
            Self::Gitsha1 => "GITSHA1",
        };
        serializer.serialize_str(variant)
    }
}
impl<'de> serde::Deserialize<'de> for digest_function::Value {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "UNKNOWN",
            "SHA256",
            "SHA1",
            "MD5",
            "VSO",
            "SHA384",
            "SHA512",
            "MURMUR3",
            "SHA256TREE",
            "BLAKE3",
            "GITSHA1",
        ];

        struct GeneratedVisitor;

        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = digest_function::Value;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                write!(formatter, "expected one of: {:?}", &FIELDS)
            }

            fn visit_i64<E>(self, v: i64) -> std::result::Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                i32::try_from(v)
                    .ok()
                    .and_then(|x| x.try_into().ok())
                    .ok_or_else(|| {
                        serde::de::Error::invalid_value(serde::de::Unexpected::Signed(v), &self)
                    })
            }

            fn visit_u64<E>(self, v: u64) -> std::result::Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                i32::try_from(v)
                    .ok()
                    .and_then(|x| x.try_into().ok())
                    .ok_or_else(|| {
                        serde::de::Error::invalid_value(serde::de::Unexpected::Unsigned(v), &self)
                    })
            }

            fn visit_str<E>(self, value: &str) -> std::result::Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                match value {
                    "UNKNOWN" => Ok(digest_function::Value::Unknown),
                    "SHA256" => Ok(digest_function::Value::Sha256),
                    "SHA1" => Ok(digest_function::Value::Sha1),
                    "MD5" => Ok(digest_function::Value::Md5),
                    "VSO" => Ok(digest_function::Value::Vso),
                    "SHA384" => Ok(digest_function::Value::Sha384),
                    "SHA512" => Ok(digest_function::Value::Sha512),
                    "MURMUR3" => Ok(digest_function::Value::Murmur3),
                    "SHA256TREE" => Ok(digest_function::Value::Sha256tree),
                    "BLAKE3" => Ok(digest_function::Value::Blake3),
                    "GITSHA1" => Ok(digest_function::Value::Gitsha1),
                    _ => Err(serde::de::Error::unknown_variant(value, FIELDS)),
                }
            }
        }
        deserializer.deserialize_any(GeneratedVisitor)
    }
}
impl serde::Serialize for Directory {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.files.is_empty() {
            len += 1;
        }
        if !self.directories.is_empty() {
            len += 1;
        }
        if !self.symlinks.is_empty() {
            len += 1;
        }
        if self.node_properties.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.Directory", len)?;
        if !self.files.is_empty() {
            struct_ser.serialize_field("files", &self.files)?;
        }
        if !self.directories.is_empty() {
            struct_ser.serialize_field("directories", &self.directories)?;
        }
        if !self.symlinks.is_empty() {
            struct_ser.serialize_field("symlinks", &self.symlinks)?;
        }
        if let Some(v) = self.node_properties.as_ref() {
            struct_ser.serialize_field("nodeProperties", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for Directory {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "files",
            "directories",
            "symlinks",
            "node_properties",
            "nodeProperties",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Files,
            Directories,
            Symlinks,
            NodeProperties,
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
                            "files" => Ok(GeneratedField::Files),
                            "directories" => Ok(GeneratedField::Directories),
                            "symlinks" => Ok(GeneratedField::Symlinks),
                            "nodeProperties" | "node_properties" => Ok(GeneratedField::NodeProperties),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = Directory;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.Directory")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<Directory, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut files__ = None;
                let mut directories__ = None;
                let mut symlinks__ = None;
                let mut node_properties__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Files => {
                            if files__.is_some() {
                                return Err(serde::de::Error::duplicate_field("files"));
                            }
                            files__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Directories => {
                            if directories__.is_some() {
                                return Err(serde::de::Error::duplicate_field("directories"));
                            }
                            directories__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Symlinks => {
                            if symlinks__.is_some() {
                                return Err(serde::de::Error::duplicate_field("symlinks"));
                            }
                            symlinks__ = Some(map_.next_value()?);
                        }
                        GeneratedField::NodeProperties => {
                            if node_properties__.is_some() {
                                return Err(serde::de::Error::duplicate_field("nodeProperties"));
                            }
                            node_properties__ = map_.next_value()?;
                        }
                    }
                }
                Ok(Directory {
                    files: files__.unwrap_or_default(),
                    directories: directories__.unwrap_or_default(),
                    symlinks: symlinks__.unwrap_or_default(),
                    node_properties: node_properties__,
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.Directory", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for DirectoryNode {
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
        if self.digest.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.DirectoryNode", len)?;
        if !self.name.is_empty() {
            struct_ser.serialize_field("name", &self.name)?;
        }
        if let Some(v) = self.digest.as_ref() {
            struct_ser.serialize_field("digest", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for DirectoryNode {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "name",
            "digest",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Name,
            Digest,
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
                            "digest" => Ok(GeneratedField::Digest),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = DirectoryNode;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.DirectoryNode")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<DirectoryNode, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut name__ = None;
                let mut digest__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Name => {
                            if name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("name"));
                            }
                            name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Digest => {
                            if digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digest"));
                            }
                            digest__ = map_.next_value()?;
                        }
                    }
                }
                Ok(DirectoryNode {
                    name: name__.unwrap_or_default(),
                    digest: digest__,
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.DirectoryNode", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ExecuteOperationMetadata {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.stage != 0 {
            len += 1;
        }
        if self.action_digest.is_some() {
            len += 1;
        }
        if !self.stdout_stream_name.is_empty() {
            len += 1;
        }
        if !self.stderr_stream_name.is_empty() {
            len += 1;
        }
        if self.partial_execution_metadata.is_some() {
            len += 1;
        }
        if self.digest_function != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.ExecuteOperationMetadata", len)?;
        if self.stage != 0 {
            let v = execution_stage::Value::try_from(self.stage)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.stage)))?;
            struct_ser.serialize_field("stage", &v)?;
        }
        if let Some(v) = self.action_digest.as_ref() {
            struct_ser.serialize_field("actionDigest", v)?;
        }
        if !self.stdout_stream_name.is_empty() {
            struct_ser.serialize_field("stdoutStreamName", &self.stdout_stream_name)?;
        }
        if !self.stderr_stream_name.is_empty() {
            struct_ser.serialize_field("stderrStreamName", &self.stderr_stream_name)?;
        }
        if let Some(v) = self.partial_execution_metadata.as_ref() {
            struct_ser.serialize_field("partialExecutionMetadata", v)?;
        }
        if self.digest_function != 0 {
            let v = digest_function::Value::try_from(self.digest_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.digest_function)))?;
            struct_ser.serialize_field("digestFunction", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ExecuteOperationMetadata {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "stage",
            "action_digest",
            "actionDigest",
            "stdout_stream_name",
            "stdoutStreamName",
            "stderr_stream_name",
            "stderrStreamName",
            "partial_execution_metadata",
            "partialExecutionMetadata",
            "digest_function",
            "digestFunction",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Stage,
            ActionDigest,
            StdoutStreamName,
            StderrStreamName,
            PartialExecutionMetadata,
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
                            "stage" => Ok(GeneratedField::Stage),
                            "actionDigest" | "action_digest" => Ok(GeneratedField::ActionDigest),
                            "stdoutStreamName" | "stdout_stream_name" => Ok(GeneratedField::StdoutStreamName),
                            "stderrStreamName" | "stderr_stream_name" => Ok(GeneratedField::StderrStreamName),
                            "partialExecutionMetadata" | "partial_execution_metadata" => Ok(GeneratedField::PartialExecutionMetadata),
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
            type Value = ExecuteOperationMetadata;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.ExecuteOperationMetadata")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ExecuteOperationMetadata, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut stage__ = None;
                let mut action_digest__ = None;
                let mut stdout_stream_name__ = None;
                let mut stderr_stream_name__ = None;
                let mut partial_execution_metadata__ = None;
                let mut digest_function__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Stage => {
                            if stage__.is_some() {
                                return Err(serde::de::Error::duplicate_field("stage"));
                            }
                            stage__ = Some(map_.next_value::<execution_stage::Value>()? as i32);
                        }
                        GeneratedField::ActionDigest => {
                            if action_digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("actionDigest"));
                            }
                            action_digest__ = map_.next_value()?;
                        }
                        GeneratedField::StdoutStreamName => {
                            if stdout_stream_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("stdoutStreamName"));
                            }
                            stdout_stream_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::StderrStreamName => {
                            if stderr_stream_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("stderrStreamName"));
                            }
                            stderr_stream_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::PartialExecutionMetadata => {
                            if partial_execution_metadata__.is_some() {
                                return Err(serde::de::Error::duplicate_field("partialExecutionMetadata"));
                            }
                            partial_execution_metadata__ = map_.next_value()?;
                        }
                        GeneratedField::DigestFunction => {
                            if digest_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digestFunction"));
                            }
                            digest_function__ = Some(map_.next_value::<digest_function::Value>()? as i32);
                        }
                    }
                }
                Ok(ExecuteOperationMetadata {
                    stage: stage__.unwrap_or_default(),
                    action_digest: action_digest__,
                    stdout_stream_name: stdout_stream_name__.unwrap_or_default(),
                    stderr_stream_name: stderr_stream_name__.unwrap_or_default(),
                    partial_execution_metadata: partial_execution_metadata__,
                    digest_function: digest_function__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.ExecuteOperationMetadata", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ExecuteRequest {
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
        if self.skip_cache_lookup {
            len += 1;
        }
        if self.action_digest.is_some() {
            len += 1;
        }
        if self.execution_policy.is_some() {
            len += 1;
        }
        if self.results_cache_policy.is_some() {
            len += 1;
        }
        if self.digest_function != 0 {
            len += 1;
        }
        if self.inline_stdout {
            len += 1;
        }
        if self.inline_stderr {
            len += 1;
        }
        if !self.inline_output_files.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.ExecuteRequest", len)?;
        if !self.instance_name.is_empty() {
            struct_ser.serialize_field("instanceName", &self.instance_name)?;
        }
        if self.skip_cache_lookup {
            struct_ser.serialize_field("skipCacheLookup", &self.skip_cache_lookup)?;
        }
        if let Some(v) = self.action_digest.as_ref() {
            struct_ser.serialize_field("actionDigest", v)?;
        }
        if let Some(v) = self.execution_policy.as_ref() {
            struct_ser.serialize_field("executionPolicy", v)?;
        }
        if let Some(v) = self.results_cache_policy.as_ref() {
            struct_ser.serialize_field("resultsCachePolicy", v)?;
        }
        if self.digest_function != 0 {
            let v = digest_function::Value::try_from(self.digest_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.digest_function)))?;
            struct_ser.serialize_field("digestFunction", &v)?;
        }
        if self.inline_stdout {
            struct_ser.serialize_field("inlineStdout", &self.inline_stdout)?;
        }
        if self.inline_stderr {
            struct_ser.serialize_field("inlineStderr", &self.inline_stderr)?;
        }
        if !self.inline_output_files.is_empty() {
            struct_ser.serialize_field("inlineOutputFiles", &self.inline_output_files)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ExecuteRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "instance_name",
            "instanceName",
            "skip_cache_lookup",
            "skipCacheLookup",
            "action_digest",
            "actionDigest",
            "execution_policy",
            "executionPolicy",
            "results_cache_policy",
            "resultsCachePolicy",
            "digest_function",
            "digestFunction",
            "inline_stdout",
            "inlineStdout",
            "inline_stderr",
            "inlineStderr",
            "inline_output_files",
            "inlineOutputFiles",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            InstanceName,
            SkipCacheLookup,
            ActionDigest,
            ExecutionPolicy,
            ResultsCachePolicy,
            DigestFunction,
            InlineStdout,
            InlineStderr,
            InlineOutputFiles,
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
                            "skipCacheLookup" | "skip_cache_lookup" => Ok(GeneratedField::SkipCacheLookup),
                            "actionDigest" | "action_digest" => Ok(GeneratedField::ActionDigest),
                            "executionPolicy" | "execution_policy" => Ok(GeneratedField::ExecutionPolicy),
                            "resultsCachePolicy" | "results_cache_policy" => Ok(GeneratedField::ResultsCachePolicy),
                            "digestFunction" | "digest_function" => Ok(GeneratedField::DigestFunction),
                            "inlineStdout" | "inline_stdout" => Ok(GeneratedField::InlineStdout),
                            "inlineStderr" | "inline_stderr" => Ok(GeneratedField::InlineStderr),
                            "inlineOutputFiles" | "inline_output_files" => Ok(GeneratedField::InlineOutputFiles),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ExecuteRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.ExecuteRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ExecuteRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut instance_name__ = None;
                let mut skip_cache_lookup__ = None;
                let mut action_digest__ = None;
                let mut execution_policy__ = None;
                let mut results_cache_policy__ = None;
                let mut digest_function__ = None;
                let mut inline_stdout__ = None;
                let mut inline_stderr__ = None;
                let mut inline_output_files__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::InstanceName => {
                            if instance_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("instanceName"));
                            }
                            instance_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::SkipCacheLookup => {
                            if skip_cache_lookup__.is_some() {
                                return Err(serde::de::Error::duplicate_field("skipCacheLookup"));
                            }
                            skip_cache_lookup__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ActionDigest => {
                            if action_digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("actionDigest"));
                            }
                            action_digest__ = map_.next_value()?;
                        }
                        GeneratedField::ExecutionPolicy => {
                            if execution_policy__.is_some() {
                                return Err(serde::de::Error::duplicate_field("executionPolicy"));
                            }
                            execution_policy__ = map_.next_value()?;
                        }
                        GeneratedField::ResultsCachePolicy => {
                            if results_cache_policy__.is_some() {
                                return Err(serde::de::Error::duplicate_field("resultsCachePolicy"));
                            }
                            results_cache_policy__ = map_.next_value()?;
                        }
                        GeneratedField::DigestFunction => {
                            if digest_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digestFunction"));
                            }
                            digest_function__ = Some(map_.next_value::<digest_function::Value>()? as i32);
                        }
                        GeneratedField::InlineStdout => {
                            if inline_stdout__.is_some() {
                                return Err(serde::de::Error::duplicate_field("inlineStdout"));
                            }
                            inline_stdout__ = Some(map_.next_value()?);
                        }
                        GeneratedField::InlineStderr => {
                            if inline_stderr__.is_some() {
                                return Err(serde::de::Error::duplicate_field("inlineStderr"));
                            }
                            inline_stderr__ = Some(map_.next_value()?);
                        }
                        GeneratedField::InlineOutputFiles => {
                            if inline_output_files__.is_some() {
                                return Err(serde::de::Error::duplicate_field("inlineOutputFiles"));
                            }
                            inline_output_files__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(ExecuteRequest {
                    instance_name: instance_name__.unwrap_or_default(),
                    skip_cache_lookup: skip_cache_lookup__.unwrap_or_default(),
                    action_digest: action_digest__,
                    execution_policy: execution_policy__,
                    results_cache_policy: results_cache_policy__,
                    digest_function: digest_function__.unwrap_or_default(),
                    inline_stdout: inline_stdout__.unwrap_or_default(),
                    inline_stderr: inline_stderr__.unwrap_or_default(),
                    inline_output_files: inline_output_files__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.ExecuteRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ExecuteResponse {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.result.is_some() {
            len += 1;
        }
        if self.cached_result {
            len += 1;
        }
        if self.status.is_some() {
            len += 1;
        }
        if !self.server_logs.is_empty() {
            len += 1;
        }
        if !self.message.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.ExecuteResponse", len)?;
        if let Some(v) = self.result.as_ref() {
            struct_ser.serialize_field("result", v)?;
        }
        if self.cached_result {
            struct_ser.serialize_field("cachedResult", &self.cached_result)?;
        }
        if let Some(v) = self.status.as_ref() {
            struct_ser.serialize_field("status", v)?;
        }
        if !self.server_logs.is_empty() {
            struct_ser.serialize_field("serverLogs", &self.server_logs)?;
        }
        if !self.message.is_empty() {
            struct_ser.serialize_field("message", &self.message)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ExecuteResponse {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "result",
            "cached_result",
            "cachedResult",
            "status",
            "server_logs",
            "serverLogs",
            "message",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Result,
            CachedResult,
            Status,
            ServerLogs,
            Message,
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
                            "result" => Ok(GeneratedField::Result),
                            "cachedResult" | "cached_result" => Ok(GeneratedField::CachedResult),
                            "status" => Ok(GeneratedField::Status),
                            "serverLogs" | "server_logs" => Ok(GeneratedField::ServerLogs),
                            "message" => Ok(GeneratedField::Message),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ExecuteResponse;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.ExecuteResponse")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ExecuteResponse, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut result__ = None;
                let mut cached_result__ = None;
                let mut status__ = None;
                let mut server_logs__ = None;
                let mut message__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Result => {
                            if result__.is_some() {
                                return Err(serde::de::Error::duplicate_field("result"));
                            }
                            result__ = map_.next_value()?;
                        }
                        GeneratedField::CachedResult => {
                            if cached_result__.is_some() {
                                return Err(serde::de::Error::duplicate_field("cachedResult"));
                            }
                            cached_result__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Status => {
                            if status__.is_some() {
                                return Err(serde::de::Error::duplicate_field("status"));
                            }
                            status__ = map_.next_value()?;
                        }
                        GeneratedField::ServerLogs => {
                            if server_logs__.is_some() {
                                return Err(serde::de::Error::duplicate_field("serverLogs"));
                            }
                            server_logs__ = Some(
                                map_.next_value::<std::collections::HashMap<_, _>>()?
                            );
                        }
                        GeneratedField::Message => {
                            if message__.is_some() {
                                return Err(serde::de::Error::duplicate_field("message"));
                            }
                            message__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(ExecuteResponse {
                    result: result__,
                    cached_result: cached_result__.unwrap_or_default(),
                    status: status__,
                    server_logs: server_logs__.unwrap_or_default(),
                    message: message__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.ExecuteResponse", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ExecutedActionMetadata {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.worker.is_empty() {
            len += 1;
        }
        if self.queued_timestamp.is_some() {
            len += 1;
        }
        if self.worker_start_timestamp.is_some() {
            len += 1;
        }
        if self.worker_completed_timestamp.is_some() {
            len += 1;
        }
        if self.input_fetch_start_timestamp.is_some() {
            len += 1;
        }
        if self.input_fetch_completed_timestamp.is_some() {
            len += 1;
        }
        if self.execution_start_timestamp.is_some() {
            len += 1;
        }
        if self.execution_completed_timestamp.is_some() {
            len += 1;
        }
        if self.virtual_execution_duration.is_some() {
            len += 1;
        }
        if self.output_upload_start_timestamp.is_some() {
            len += 1;
        }
        if self.output_upload_completed_timestamp.is_some() {
            len += 1;
        }
        if !self.auxiliary_metadata.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.ExecutedActionMetadata", len)?;
        if !self.worker.is_empty() {
            struct_ser.serialize_field("worker", &self.worker)?;
        }
        if let Some(v) = self.queued_timestamp.as_ref() {
            struct_ser.serialize_field("queuedTimestamp", v)?;
        }
        if let Some(v) = self.worker_start_timestamp.as_ref() {
            struct_ser.serialize_field("workerStartTimestamp", v)?;
        }
        if let Some(v) = self.worker_completed_timestamp.as_ref() {
            struct_ser.serialize_field("workerCompletedTimestamp", v)?;
        }
        if let Some(v) = self.input_fetch_start_timestamp.as_ref() {
            struct_ser.serialize_field("inputFetchStartTimestamp", v)?;
        }
        if let Some(v) = self.input_fetch_completed_timestamp.as_ref() {
            struct_ser.serialize_field("inputFetchCompletedTimestamp", v)?;
        }
        if let Some(v) = self.execution_start_timestamp.as_ref() {
            struct_ser.serialize_field("executionStartTimestamp", v)?;
        }
        if let Some(v) = self.execution_completed_timestamp.as_ref() {
            struct_ser.serialize_field("executionCompletedTimestamp", v)?;
        }
        if let Some(v) = self.virtual_execution_duration.as_ref() {
            struct_ser.serialize_field("virtualExecutionDuration", v)?;
        }
        if let Some(v) = self.output_upload_start_timestamp.as_ref() {
            struct_ser.serialize_field("outputUploadStartTimestamp", v)?;
        }
        if let Some(v) = self.output_upload_completed_timestamp.as_ref() {
            struct_ser.serialize_field("outputUploadCompletedTimestamp", v)?;
        }
        if !self.auxiliary_metadata.is_empty() {
            struct_ser.serialize_field("auxiliaryMetadata", &self.auxiliary_metadata)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ExecutedActionMetadata {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "worker",
            "queued_timestamp",
            "queuedTimestamp",
            "worker_start_timestamp",
            "workerStartTimestamp",
            "worker_completed_timestamp",
            "workerCompletedTimestamp",
            "input_fetch_start_timestamp",
            "inputFetchStartTimestamp",
            "input_fetch_completed_timestamp",
            "inputFetchCompletedTimestamp",
            "execution_start_timestamp",
            "executionStartTimestamp",
            "execution_completed_timestamp",
            "executionCompletedTimestamp",
            "virtual_execution_duration",
            "virtualExecutionDuration",
            "output_upload_start_timestamp",
            "outputUploadStartTimestamp",
            "output_upload_completed_timestamp",
            "outputUploadCompletedTimestamp",
            "auxiliary_metadata",
            "auxiliaryMetadata",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Worker,
            QueuedTimestamp,
            WorkerStartTimestamp,
            WorkerCompletedTimestamp,
            InputFetchStartTimestamp,
            InputFetchCompletedTimestamp,
            ExecutionStartTimestamp,
            ExecutionCompletedTimestamp,
            VirtualExecutionDuration,
            OutputUploadStartTimestamp,
            OutputUploadCompletedTimestamp,
            AuxiliaryMetadata,
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
                            "worker" => Ok(GeneratedField::Worker),
                            "queuedTimestamp" | "queued_timestamp" => Ok(GeneratedField::QueuedTimestamp),
                            "workerStartTimestamp" | "worker_start_timestamp" => Ok(GeneratedField::WorkerStartTimestamp),
                            "workerCompletedTimestamp" | "worker_completed_timestamp" => Ok(GeneratedField::WorkerCompletedTimestamp),
                            "inputFetchStartTimestamp" | "input_fetch_start_timestamp" => Ok(GeneratedField::InputFetchStartTimestamp),
                            "inputFetchCompletedTimestamp" | "input_fetch_completed_timestamp" => Ok(GeneratedField::InputFetchCompletedTimestamp),
                            "executionStartTimestamp" | "execution_start_timestamp" => Ok(GeneratedField::ExecutionStartTimestamp),
                            "executionCompletedTimestamp" | "execution_completed_timestamp" => Ok(GeneratedField::ExecutionCompletedTimestamp),
                            "virtualExecutionDuration" | "virtual_execution_duration" => Ok(GeneratedField::VirtualExecutionDuration),
                            "outputUploadStartTimestamp" | "output_upload_start_timestamp" => Ok(GeneratedField::OutputUploadStartTimestamp),
                            "outputUploadCompletedTimestamp" | "output_upload_completed_timestamp" => Ok(GeneratedField::OutputUploadCompletedTimestamp),
                            "auxiliaryMetadata" | "auxiliary_metadata" => Ok(GeneratedField::AuxiliaryMetadata),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ExecutedActionMetadata;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.ExecutedActionMetadata")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ExecutedActionMetadata, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut worker__ = None;
                let mut queued_timestamp__ = None;
                let mut worker_start_timestamp__ = None;
                let mut worker_completed_timestamp__ = None;
                let mut input_fetch_start_timestamp__ = None;
                let mut input_fetch_completed_timestamp__ = None;
                let mut execution_start_timestamp__ = None;
                let mut execution_completed_timestamp__ = None;
                let mut virtual_execution_duration__ = None;
                let mut output_upload_start_timestamp__ = None;
                let mut output_upload_completed_timestamp__ = None;
                let mut auxiliary_metadata__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Worker => {
                            if worker__.is_some() {
                                return Err(serde::de::Error::duplicate_field("worker"));
                            }
                            worker__ = Some(map_.next_value()?);
                        }
                        GeneratedField::QueuedTimestamp => {
                            if queued_timestamp__.is_some() {
                                return Err(serde::de::Error::duplicate_field("queuedTimestamp"));
                            }
                            queued_timestamp__ = map_.next_value()?;
                        }
                        GeneratedField::WorkerStartTimestamp => {
                            if worker_start_timestamp__.is_some() {
                                return Err(serde::de::Error::duplicate_field("workerStartTimestamp"));
                            }
                            worker_start_timestamp__ = map_.next_value()?;
                        }
                        GeneratedField::WorkerCompletedTimestamp => {
                            if worker_completed_timestamp__.is_some() {
                                return Err(serde::de::Error::duplicate_field("workerCompletedTimestamp"));
                            }
                            worker_completed_timestamp__ = map_.next_value()?;
                        }
                        GeneratedField::InputFetchStartTimestamp => {
                            if input_fetch_start_timestamp__.is_some() {
                                return Err(serde::de::Error::duplicate_field("inputFetchStartTimestamp"));
                            }
                            input_fetch_start_timestamp__ = map_.next_value()?;
                        }
                        GeneratedField::InputFetchCompletedTimestamp => {
                            if input_fetch_completed_timestamp__.is_some() {
                                return Err(serde::de::Error::duplicate_field("inputFetchCompletedTimestamp"));
                            }
                            input_fetch_completed_timestamp__ = map_.next_value()?;
                        }
                        GeneratedField::ExecutionStartTimestamp => {
                            if execution_start_timestamp__.is_some() {
                                return Err(serde::de::Error::duplicate_field("executionStartTimestamp"));
                            }
                            execution_start_timestamp__ = map_.next_value()?;
                        }
                        GeneratedField::ExecutionCompletedTimestamp => {
                            if execution_completed_timestamp__.is_some() {
                                return Err(serde::de::Error::duplicate_field("executionCompletedTimestamp"));
                            }
                            execution_completed_timestamp__ = map_.next_value()?;
                        }
                        GeneratedField::VirtualExecutionDuration => {
                            if virtual_execution_duration__.is_some() {
                                return Err(serde::de::Error::duplicate_field("virtualExecutionDuration"));
                            }
                            virtual_execution_duration__ = map_.next_value()?;
                        }
                        GeneratedField::OutputUploadStartTimestamp => {
                            if output_upload_start_timestamp__.is_some() {
                                return Err(serde::de::Error::duplicate_field("outputUploadStartTimestamp"));
                            }
                            output_upload_start_timestamp__ = map_.next_value()?;
                        }
                        GeneratedField::OutputUploadCompletedTimestamp => {
                            if output_upload_completed_timestamp__.is_some() {
                                return Err(serde::de::Error::duplicate_field("outputUploadCompletedTimestamp"));
                            }
                            output_upload_completed_timestamp__ = map_.next_value()?;
                        }
                        GeneratedField::AuxiliaryMetadata => {
                            if auxiliary_metadata__.is_some() {
                                return Err(serde::de::Error::duplicate_field("auxiliaryMetadata"));
                            }
                            auxiliary_metadata__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(ExecutedActionMetadata {
                    worker: worker__.unwrap_or_default(),
                    queued_timestamp: queued_timestamp__,
                    worker_start_timestamp: worker_start_timestamp__,
                    worker_completed_timestamp: worker_completed_timestamp__,
                    input_fetch_start_timestamp: input_fetch_start_timestamp__,
                    input_fetch_completed_timestamp: input_fetch_completed_timestamp__,
                    execution_start_timestamp: execution_start_timestamp__,
                    execution_completed_timestamp: execution_completed_timestamp__,
                    virtual_execution_duration: virtual_execution_duration__,
                    output_upload_start_timestamp: output_upload_start_timestamp__,
                    output_upload_completed_timestamp: output_upload_completed_timestamp__,
                    auxiliary_metadata: auxiliary_metadata__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.ExecutedActionMetadata", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ExecutionCapabilities {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.digest_function != 0 {
            len += 1;
        }
        if self.exec_enabled {
            len += 1;
        }
        if self.execution_priority_capabilities.is_some() {
            len += 1;
        }
        if !self.supported_node_properties.is_empty() {
            len += 1;
        }
        if !self.digest_functions.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.ExecutionCapabilities", len)?;
        if self.digest_function != 0 {
            let v = digest_function::Value::try_from(self.digest_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.digest_function)))?;
            struct_ser.serialize_field("digestFunction", &v)?;
        }
        if self.exec_enabled {
            struct_ser.serialize_field("execEnabled", &self.exec_enabled)?;
        }
        if let Some(v) = self.execution_priority_capabilities.as_ref() {
            struct_ser.serialize_field("executionPriorityCapabilities", v)?;
        }
        if !self.supported_node_properties.is_empty() {
            struct_ser.serialize_field("supportedNodeProperties", &self.supported_node_properties)?;
        }
        if !self.digest_functions.is_empty() {
            let v = self.digest_functions.iter().cloned().map(|v| {
                digest_function::Value::try_from(v)
                    .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", v)))
                }).collect::<std::result::Result<Vec<_>, _>>()?;
            struct_ser.serialize_field("digestFunctions", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ExecutionCapabilities {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "digest_function",
            "digestFunction",
            "exec_enabled",
            "execEnabled",
            "execution_priority_capabilities",
            "executionPriorityCapabilities",
            "supported_node_properties",
            "supportedNodeProperties",
            "digest_functions",
            "digestFunctions",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            DigestFunction,
            ExecEnabled,
            ExecutionPriorityCapabilities,
            SupportedNodeProperties,
            DigestFunctions,
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
                            "digestFunction" | "digest_function" => Ok(GeneratedField::DigestFunction),
                            "execEnabled" | "exec_enabled" => Ok(GeneratedField::ExecEnabled),
                            "executionPriorityCapabilities" | "execution_priority_capabilities" => Ok(GeneratedField::ExecutionPriorityCapabilities),
                            "supportedNodeProperties" | "supported_node_properties" => Ok(GeneratedField::SupportedNodeProperties),
                            "digestFunctions" | "digest_functions" => Ok(GeneratedField::DigestFunctions),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ExecutionCapabilities;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.ExecutionCapabilities")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ExecutionCapabilities, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut digest_function__ = None;
                let mut exec_enabled__ = None;
                let mut execution_priority_capabilities__ = None;
                let mut supported_node_properties__ = None;
                let mut digest_functions__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::DigestFunction => {
                            if digest_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digestFunction"));
                            }
                            digest_function__ = Some(map_.next_value::<digest_function::Value>()? as i32);
                        }
                        GeneratedField::ExecEnabled => {
                            if exec_enabled__.is_some() {
                                return Err(serde::de::Error::duplicate_field("execEnabled"));
                            }
                            exec_enabled__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ExecutionPriorityCapabilities => {
                            if execution_priority_capabilities__.is_some() {
                                return Err(serde::de::Error::duplicate_field("executionPriorityCapabilities"));
                            }
                            execution_priority_capabilities__ = map_.next_value()?;
                        }
                        GeneratedField::SupportedNodeProperties => {
                            if supported_node_properties__.is_some() {
                                return Err(serde::de::Error::duplicate_field("supportedNodeProperties"));
                            }
                            supported_node_properties__ = Some(map_.next_value()?);
                        }
                        GeneratedField::DigestFunctions => {
                            if digest_functions__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digestFunctions"));
                            }
                            digest_functions__ = Some(map_.next_value::<Vec<digest_function::Value>>()?.into_iter().map(|x| x as i32).collect());
                        }
                    }
                }
                Ok(ExecutionCapabilities {
                    digest_function: digest_function__.unwrap_or_default(),
                    exec_enabled: exec_enabled__.unwrap_or_default(),
                    execution_priority_capabilities: execution_priority_capabilities__,
                    supported_node_properties: supported_node_properties__.unwrap_or_default(),
                    digest_functions: digest_functions__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.ExecutionCapabilities", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ExecutionPolicy {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.priority != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.ExecutionPolicy", len)?;
        if self.priority != 0 {
            struct_ser.serialize_field("priority", &self.priority)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ExecutionPolicy {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "priority",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Priority,
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
                            "priority" => Ok(GeneratedField::Priority),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ExecutionPolicy;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.ExecutionPolicy")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ExecutionPolicy, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut priority__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Priority => {
                            if priority__.is_some() {
                                return Err(serde::de::Error::duplicate_field("priority"));
                            }
                            priority__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                    }
                }
                Ok(ExecutionPolicy {
                    priority: priority__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.ExecutionPolicy", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ExecutionStage {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let len = 0;
        let struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.ExecutionStage", len)?;
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ExecutionStage {
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
            type Value = ExecutionStage;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.ExecutionStage")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ExecutionStage, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                while map_.next_key::<GeneratedField>()?.is_some() {
                    let _ = map_.next_value::<serde::de::IgnoredAny>()?;
                }
                Ok(ExecutionStage {
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.ExecutionStage", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for execution_stage::Value {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let variant = match self {
            Self::Unknown => "UNKNOWN",
            Self::CacheCheck => "CACHE_CHECK",
            Self::Queued => "QUEUED",
            Self::Executing => "EXECUTING",
            Self::Completed => "COMPLETED",
        };
        serializer.serialize_str(variant)
    }
}
impl<'de> serde::Deserialize<'de> for execution_stage::Value {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "UNKNOWN",
            "CACHE_CHECK",
            "QUEUED",
            "EXECUTING",
            "COMPLETED",
        ];

        struct GeneratedVisitor;

        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = execution_stage::Value;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                write!(formatter, "expected one of: {:?}", &FIELDS)
            }

            fn visit_i64<E>(self, v: i64) -> std::result::Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                i32::try_from(v)
                    .ok()
                    .and_then(|x| x.try_into().ok())
                    .ok_or_else(|| {
                        serde::de::Error::invalid_value(serde::de::Unexpected::Signed(v), &self)
                    })
            }

            fn visit_u64<E>(self, v: u64) -> std::result::Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                i32::try_from(v)
                    .ok()
                    .and_then(|x| x.try_into().ok())
                    .ok_or_else(|| {
                        serde::de::Error::invalid_value(serde::de::Unexpected::Unsigned(v), &self)
                    })
            }

            fn visit_str<E>(self, value: &str) -> std::result::Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                match value {
                    "UNKNOWN" => Ok(execution_stage::Value::Unknown),
                    "CACHE_CHECK" => Ok(execution_stage::Value::CacheCheck),
                    "QUEUED" => Ok(execution_stage::Value::Queued),
                    "EXECUTING" => Ok(execution_stage::Value::Executing),
                    "COMPLETED" => Ok(execution_stage::Value::Completed),
                    _ => Err(serde::de::Error::unknown_variant(value, FIELDS)),
                }
            }
        }
        deserializer.deserialize_any(GeneratedVisitor)
    }
}
impl serde::Serialize for FastCdc2020Params {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.avg_chunk_size_bytes != 0 {
            len += 1;
        }
        if self.seed != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.FastCdc2020Params", len)?;
        if self.avg_chunk_size_bytes != 0 {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("avgChunkSizeBytes", ToString::to_string(&self.avg_chunk_size_bytes).as_str())?;
        }
        if self.seed != 0 {
            struct_ser.serialize_field("seed", &self.seed)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for FastCdc2020Params {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "avg_chunk_size_bytes",
            "avgChunkSizeBytes",
            "seed",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            AvgChunkSizeBytes,
            Seed,
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
                            "avgChunkSizeBytes" | "avg_chunk_size_bytes" => Ok(GeneratedField::AvgChunkSizeBytes),
                            "seed" => Ok(GeneratedField::Seed),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = FastCdc2020Params;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.FastCdc2020Params")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<FastCdc2020Params, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut avg_chunk_size_bytes__ = None;
                let mut seed__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::AvgChunkSizeBytes => {
                            if avg_chunk_size_bytes__.is_some() {
                                return Err(serde::de::Error::duplicate_field("avgChunkSizeBytes"));
                            }
                            avg_chunk_size_bytes__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Seed => {
                            if seed__.is_some() {
                                return Err(serde::de::Error::duplicate_field("seed"));
                            }
                            seed__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                    }
                }
                Ok(FastCdc2020Params {
                    avg_chunk_size_bytes: avg_chunk_size_bytes__.unwrap_or_default(),
                    seed: seed__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.FastCdc2020Params", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for FileNode {
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
        if self.digest.is_some() {
            len += 1;
        }
        if self.is_executable {
            len += 1;
        }
        if self.node_properties.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.FileNode", len)?;
        if !self.name.is_empty() {
            struct_ser.serialize_field("name", &self.name)?;
        }
        if let Some(v) = self.digest.as_ref() {
            struct_ser.serialize_field("digest", v)?;
        }
        if self.is_executable {
            struct_ser.serialize_field("isExecutable", &self.is_executable)?;
        }
        if let Some(v) = self.node_properties.as_ref() {
            struct_ser.serialize_field("nodeProperties", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for FileNode {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "name",
            "digest",
            "is_executable",
            "isExecutable",
            "node_properties",
            "nodeProperties",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Name,
            Digest,
            IsExecutable,
            NodeProperties,
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
                            "digest" => Ok(GeneratedField::Digest),
                            "isExecutable" | "is_executable" => Ok(GeneratedField::IsExecutable),
                            "nodeProperties" | "node_properties" => Ok(GeneratedField::NodeProperties),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = FileNode;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.FileNode")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<FileNode, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut name__ = None;
                let mut digest__ = None;
                let mut is_executable__ = None;
                let mut node_properties__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Name => {
                            if name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("name"));
                            }
                            name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Digest => {
                            if digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digest"));
                            }
                            digest__ = map_.next_value()?;
                        }
                        GeneratedField::IsExecutable => {
                            if is_executable__.is_some() {
                                return Err(serde::de::Error::duplicate_field("isExecutable"));
                            }
                            is_executable__ = Some(map_.next_value()?);
                        }
                        GeneratedField::NodeProperties => {
                            if node_properties__.is_some() {
                                return Err(serde::de::Error::duplicate_field("nodeProperties"));
                            }
                            node_properties__ = map_.next_value()?;
                        }
                    }
                }
                Ok(FileNode {
                    name: name__.unwrap_or_default(),
                    digest: digest__,
                    is_executable: is_executable__.unwrap_or_default(),
                    node_properties: node_properties__,
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.FileNode", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for FindMissingBlobsRequest {
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
        if !self.blob_digests.is_empty() {
            len += 1;
        }
        if self.digest_function != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.FindMissingBlobsRequest", len)?;
        if !self.instance_name.is_empty() {
            struct_ser.serialize_field("instanceName", &self.instance_name)?;
        }
        if !self.blob_digests.is_empty() {
            struct_ser.serialize_field("blobDigests", &self.blob_digests)?;
        }
        if self.digest_function != 0 {
            let v = digest_function::Value::try_from(self.digest_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.digest_function)))?;
            struct_ser.serialize_field("digestFunction", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for FindMissingBlobsRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "instance_name",
            "instanceName",
            "blob_digests",
            "blobDigests",
            "digest_function",
            "digestFunction",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            InstanceName,
            BlobDigests,
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
                            "blobDigests" | "blob_digests" => Ok(GeneratedField::BlobDigests),
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
            type Value = FindMissingBlobsRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.FindMissingBlobsRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<FindMissingBlobsRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut instance_name__ = None;
                let mut blob_digests__ = None;
                let mut digest_function__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::InstanceName => {
                            if instance_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("instanceName"));
                            }
                            instance_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::BlobDigests => {
                            if blob_digests__.is_some() {
                                return Err(serde::de::Error::duplicate_field("blobDigests"));
                            }
                            blob_digests__ = Some(map_.next_value()?);
                        }
                        GeneratedField::DigestFunction => {
                            if digest_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digestFunction"));
                            }
                            digest_function__ = Some(map_.next_value::<digest_function::Value>()? as i32);
                        }
                    }
                }
                Ok(FindMissingBlobsRequest {
                    instance_name: instance_name__.unwrap_or_default(),
                    blob_digests: blob_digests__.unwrap_or_default(),
                    digest_function: digest_function__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.FindMissingBlobsRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for FindMissingBlobsResponse {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.missing_blob_digests.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.FindMissingBlobsResponse", len)?;
        if !self.missing_blob_digests.is_empty() {
            struct_ser.serialize_field("missingBlobDigests", &self.missing_blob_digests)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for FindMissingBlobsResponse {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "missing_blob_digests",
            "missingBlobDigests",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            MissingBlobDigests,
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
                            "missingBlobDigests" | "missing_blob_digests" => Ok(GeneratedField::MissingBlobDigests),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = FindMissingBlobsResponse;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.FindMissingBlobsResponse")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<FindMissingBlobsResponse, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut missing_blob_digests__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::MissingBlobDigests => {
                            if missing_blob_digests__.is_some() {
                                return Err(serde::de::Error::duplicate_field("missingBlobDigests"));
                            }
                            missing_blob_digests__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(FindMissingBlobsResponse {
                    missing_blob_digests: missing_blob_digests__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.FindMissingBlobsResponse", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for GetActionResultRequest {
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
        if self.action_digest.is_some() {
            len += 1;
        }
        if self.inline_stdout {
            len += 1;
        }
        if self.inline_stderr {
            len += 1;
        }
        if !self.inline_output_files.is_empty() {
            len += 1;
        }
        if self.digest_function != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.GetActionResultRequest", len)?;
        if !self.instance_name.is_empty() {
            struct_ser.serialize_field("instanceName", &self.instance_name)?;
        }
        if let Some(v) = self.action_digest.as_ref() {
            struct_ser.serialize_field("actionDigest", v)?;
        }
        if self.inline_stdout {
            struct_ser.serialize_field("inlineStdout", &self.inline_stdout)?;
        }
        if self.inline_stderr {
            struct_ser.serialize_field("inlineStderr", &self.inline_stderr)?;
        }
        if !self.inline_output_files.is_empty() {
            struct_ser.serialize_field("inlineOutputFiles", &self.inline_output_files)?;
        }
        if self.digest_function != 0 {
            let v = digest_function::Value::try_from(self.digest_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.digest_function)))?;
            struct_ser.serialize_field("digestFunction", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for GetActionResultRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "instance_name",
            "instanceName",
            "action_digest",
            "actionDigest",
            "inline_stdout",
            "inlineStdout",
            "inline_stderr",
            "inlineStderr",
            "inline_output_files",
            "inlineOutputFiles",
            "digest_function",
            "digestFunction",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            InstanceName,
            ActionDigest,
            InlineStdout,
            InlineStderr,
            InlineOutputFiles,
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
                            "actionDigest" | "action_digest" => Ok(GeneratedField::ActionDigest),
                            "inlineStdout" | "inline_stdout" => Ok(GeneratedField::InlineStdout),
                            "inlineStderr" | "inline_stderr" => Ok(GeneratedField::InlineStderr),
                            "inlineOutputFiles" | "inline_output_files" => Ok(GeneratedField::InlineOutputFiles),
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
            type Value = GetActionResultRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.GetActionResultRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<GetActionResultRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut instance_name__ = None;
                let mut action_digest__ = None;
                let mut inline_stdout__ = None;
                let mut inline_stderr__ = None;
                let mut inline_output_files__ = None;
                let mut digest_function__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::InstanceName => {
                            if instance_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("instanceName"));
                            }
                            instance_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ActionDigest => {
                            if action_digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("actionDigest"));
                            }
                            action_digest__ = map_.next_value()?;
                        }
                        GeneratedField::InlineStdout => {
                            if inline_stdout__.is_some() {
                                return Err(serde::de::Error::duplicate_field("inlineStdout"));
                            }
                            inline_stdout__ = Some(map_.next_value()?);
                        }
                        GeneratedField::InlineStderr => {
                            if inline_stderr__.is_some() {
                                return Err(serde::de::Error::duplicate_field("inlineStderr"));
                            }
                            inline_stderr__ = Some(map_.next_value()?);
                        }
                        GeneratedField::InlineOutputFiles => {
                            if inline_output_files__.is_some() {
                                return Err(serde::de::Error::duplicate_field("inlineOutputFiles"));
                            }
                            inline_output_files__ = Some(map_.next_value()?);
                        }
                        GeneratedField::DigestFunction => {
                            if digest_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digestFunction"));
                            }
                            digest_function__ = Some(map_.next_value::<digest_function::Value>()? as i32);
                        }
                    }
                }
                Ok(GetActionResultRequest {
                    instance_name: instance_name__.unwrap_or_default(),
                    action_digest: action_digest__,
                    inline_stdout: inline_stdout__.unwrap_or_default(),
                    inline_stderr: inline_stderr__.unwrap_or_default(),
                    inline_output_files: inline_output_files__.unwrap_or_default(),
                    digest_function: digest_function__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.GetActionResultRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for GetCapabilitiesRequest {
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
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.GetCapabilitiesRequest", len)?;
        if !self.instance_name.is_empty() {
            struct_ser.serialize_field("instanceName", &self.instance_name)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for GetCapabilitiesRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "instance_name",
            "instanceName",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            InstanceName,
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
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = GetCapabilitiesRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.GetCapabilitiesRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<GetCapabilitiesRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut instance_name__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::InstanceName => {
                            if instance_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("instanceName"));
                            }
                            instance_name__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(GetCapabilitiesRequest {
                    instance_name: instance_name__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.GetCapabilitiesRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for GetTreeRequest {
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
        if self.root_digest.is_some() {
            len += 1;
        }
        if self.page_size != 0 {
            len += 1;
        }
        if !self.page_token.is_empty() {
            len += 1;
        }
        if self.digest_function != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.GetTreeRequest", len)?;
        if !self.instance_name.is_empty() {
            struct_ser.serialize_field("instanceName", &self.instance_name)?;
        }
        if let Some(v) = self.root_digest.as_ref() {
            struct_ser.serialize_field("rootDigest", v)?;
        }
        if self.page_size != 0 {
            struct_ser.serialize_field("pageSize", &self.page_size)?;
        }
        if !self.page_token.is_empty() {
            struct_ser.serialize_field("pageToken", &self.page_token)?;
        }
        if self.digest_function != 0 {
            let v = digest_function::Value::try_from(self.digest_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.digest_function)))?;
            struct_ser.serialize_field("digestFunction", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for GetTreeRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "instance_name",
            "instanceName",
            "root_digest",
            "rootDigest",
            "page_size",
            "pageSize",
            "page_token",
            "pageToken",
            "digest_function",
            "digestFunction",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            InstanceName,
            RootDigest,
            PageSize,
            PageToken,
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
                            "rootDigest" | "root_digest" => Ok(GeneratedField::RootDigest),
                            "pageSize" | "page_size" => Ok(GeneratedField::PageSize),
                            "pageToken" | "page_token" => Ok(GeneratedField::PageToken),
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
            type Value = GetTreeRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.GetTreeRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<GetTreeRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut instance_name__ = None;
                let mut root_digest__ = None;
                let mut page_size__ = None;
                let mut page_token__ = None;
                let mut digest_function__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::InstanceName => {
                            if instance_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("instanceName"));
                            }
                            instance_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::RootDigest => {
                            if root_digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("rootDigest"));
                            }
                            root_digest__ = map_.next_value()?;
                        }
                        GeneratedField::PageSize => {
                            if page_size__.is_some() {
                                return Err(serde::de::Error::duplicate_field("pageSize"));
                            }
                            page_size__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::PageToken => {
                            if page_token__.is_some() {
                                return Err(serde::de::Error::duplicate_field("pageToken"));
                            }
                            page_token__ = Some(map_.next_value()?);
                        }
                        GeneratedField::DigestFunction => {
                            if digest_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digestFunction"));
                            }
                            digest_function__ = Some(map_.next_value::<digest_function::Value>()? as i32);
                        }
                    }
                }
                Ok(GetTreeRequest {
                    instance_name: instance_name__.unwrap_or_default(),
                    root_digest: root_digest__,
                    page_size: page_size__.unwrap_or_default(),
                    page_token: page_token__.unwrap_or_default(),
                    digest_function: digest_function__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.GetTreeRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for GetTreeResponse {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.directories.is_empty() {
            len += 1;
        }
        if !self.next_page_token.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.GetTreeResponse", len)?;
        if !self.directories.is_empty() {
            struct_ser.serialize_field("directories", &self.directories)?;
        }
        if !self.next_page_token.is_empty() {
            struct_ser.serialize_field("nextPageToken", &self.next_page_token)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for GetTreeResponse {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "directories",
            "next_page_token",
            "nextPageToken",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Directories,
            NextPageToken,
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
                            "directories" => Ok(GeneratedField::Directories),
                            "nextPageToken" | "next_page_token" => Ok(GeneratedField::NextPageToken),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = GetTreeResponse;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.GetTreeResponse")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<GetTreeResponse, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut directories__ = None;
                let mut next_page_token__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Directories => {
                            if directories__.is_some() {
                                return Err(serde::de::Error::duplicate_field("directories"));
                            }
                            directories__ = Some(map_.next_value()?);
                        }
                        GeneratedField::NextPageToken => {
                            if next_page_token__.is_some() {
                                return Err(serde::de::Error::duplicate_field("nextPageToken"));
                            }
                            next_page_token__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(GetTreeResponse {
                    directories: directories__.unwrap_or_default(),
                    next_page_token: next_page_token__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.GetTreeResponse", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for LogFile {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.digest.is_some() {
            len += 1;
        }
        if self.human_readable {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.LogFile", len)?;
        if let Some(v) = self.digest.as_ref() {
            struct_ser.serialize_field("digest", v)?;
        }
        if self.human_readable {
            struct_ser.serialize_field("humanReadable", &self.human_readable)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for LogFile {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "digest",
            "human_readable",
            "humanReadable",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Digest,
            HumanReadable,
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
                            "digest" => Ok(GeneratedField::Digest),
                            "humanReadable" | "human_readable" => Ok(GeneratedField::HumanReadable),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = LogFile;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.LogFile")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<LogFile, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut digest__ = None;
                let mut human_readable__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Digest => {
                            if digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digest"));
                            }
                            digest__ = map_.next_value()?;
                        }
                        GeneratedField::HumanReadable => {
                            if human_readable__.is_some() {
                                return Err(serde::de::Error::duplicate_field("humanReadable"));
                            }
                            human_readable__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(LogFile {
                    digest: digest__,
                    human_readable: human_readable__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.LogFile", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for NodeProperties {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.properties.is_empty() {
            len += 1;
        }
        if self.mtime.is_some() {
            len += 1;
        }
        if self.unix_mode.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.NodeProperties", len)?;
        if !self.properties.is_empty() {
            struct_ser.serialize_field("properties", &self.properties)?;
        }
        if let Some(v) = self.mtime.as_ref() {
            struct_ser.serialize_field("mtime", v)?;
        }
        if let Some(v) = self.unix_mode.as_ref() {
            struct_ser.serialize_field("unixMode", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for NodeProperties {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "properties",
            "mtime",
            "unix_mode",
            "unixMode",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Properties,
            Mtime,
            UnixMode,
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
                            "properties" => Ok(GeneratedField::Properties),
                            "mtime" => Ok(GeneratedField::Mtime),
                            "unixMode" | "unix_mode" => Ok(GeneratedField::UnixMode),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = NodeProperties;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.NodeProperties")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<NodeProperties, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut properties__ = None;
                let mut mtime__ = None;
                let mut unix_mode__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Properties => {
                            if properties__.is_some() {
                                return Err(serde::de::Error::duplicate_field("properties"));
                            }
                            properties__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Mtime => {
                            if mtime__.is_some() {
                                return Err(serde::de::Error::duplicate_field("mtime"));
                            }
                            mtime__ = map_.next_value()?;
                        }
                        GeneratedField::UnixMode => {
                            if unix_mode__.is_some() {
                                return Err(serde::de::Error::duplicate_field("unixMode"));
                            }
                            unix_mode__ = map_.next_value()?;
                        }
                    }
                }
                Ok(NodeProperties {
                    properties: properties__.unwrap_or_default(),
                    mtime: mtime__,
                    unix_mode: unix_mode__,
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.NodeProperties", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for NodeProperty {
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
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.NodeProperty", len)?;
        if !self.name.is_empty() {
            struct_ser.serialize_field("name", &self.name)?;
        }
        if !self.value.is_empty() {
            struct_ser.serialize_field("value", &self.value)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for NodeProperty {
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
            type Value = NodeProperty;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.NodeProperty")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<NodeProperty, V::Error>
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
                Ok(NodeProperty {
                    name: name__.unwrap_or_default(),
                    value: value__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.NodeProperty", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for OutputDirectory {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.path.is_empty() {
            len += 1;
        }
        if self.tree_digest.is_some() {
            len += 1;
        }
        if self.is_topologically_sorted {
            len += 1;
        }
        if self.root_directory_digest.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.OutputDirectory", len)?;
        if !self.path.is_empty() {
            struct_ser.serialize_field("path", &self.path)?;
        }
        if let Some(v) = self.tree_digest.as_ref() {
            struct_ser.serialize_field("treeDigest", v)?;
        }
        if self.is_topologically_sorted {
            struct_ser.serialize_field("isTopologicallySorted", &self.is_topologically_sorted)?;
        }
        if let Some(v) = self.root_directory_digest.as_ref() {
            struct_ser.serialize_field("rootDirectoryDigest", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for OutputDirectory {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "path",
            "tree_digest",
            "treeDigest",
            "is_topologically_sorted",
            "isTopologicallySorted",
            "root_directory_digest",
            "rootDirectoryDigest",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Path,
            TreeDigest,
            IsTopologicallySorted,
            RootDirectoryDigest,
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
                            "path" => Ok(GeneratedField::Path),
                            "treeDigest" | "tree_digest" => Ok(GeneratedField::TreeDigest),
                            "isTopologicallySorted" | "is_topologically_sorted" => Ok(GeneratedField::IsTopologicallySorted),
                            "rootDirectoryDigest" | "root_directory_digest" => Ok(GeneratedField::RootDirectoryDigest),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = OutputDirectory;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.OutputDirectory")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<OutputDirectory, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut path__ = None;
                let mut tree_digest__ = None;
                let mut is_topologically_sorted__ = None;
                let mut root_directory_digest__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Path => {
                            if path__.is_some() {
                                return Err(serde::de::Error::duplicate_field("path"));
                            }
                            path__ = Some(map_.next_value()?);
                        }
                        GeneratedField::TreeDigest => {
                            if tree_digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("treeDigest"));
                            }
                            tree_digest__ = map_.next_value()?;
                        }
                        GeneratedField::IsTopologicallySorted => {
                            if is_topologically_sorted__.is_some() {
                                return Err(serde::de::Error::duplicate_field("isTopologicallySorted"));
                            }
                            is_topologically_sorted__ = Some(map_.next_value()?);
                        }
                        GeneratedField::RootDirectoryDigest => {
                            if root_directory_digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("rootDirectoryDigest"));
                            }
                            root_directory_digest__ = map_.next_value()?;
                        }
                    }
                }
                Ok(OutputDirectory {
                    path: path__.unwrap_or_default(),
                    tree_digest: tree_digest__,
                    is_topologically_sorted: is_topologically_sorted__.unwrap_or_default(),
                    root_directory_digest: root_directory_digest__,
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.OutputDirectory", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for OutputFile {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.path.is_empty() {
            len += 1;
        }
        if self.digest.is_some() {
            len += 1;
        }
        if self.is_executable {
            len += 1;
        }
        if !self.contents.is_empty() {
            len += 1;
        }
        if self.node_properties.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.OutputFile", len)?;
        if !self.path.is_empty() {
            struct_ser.serialize_field("path", &self.path)?;
        }
        if let Some(v) = self.digest.as_ref() {
            struct_ser.serialize_field("digest", v)?;
        }
        if self.is_executable {
            struct_ser.serialize_field("isExecutable", &self.is_executable)?;
        }
        if !self.contents.is_empty() {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("contents", pbjson::private::base64::encode(&self.contents).as_str())?;
        }
        if let Some(v) = self.node_properties.as_ref() {
            struct_ser.serialize_field("nodeProperties", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for OutputFile {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "path",
            "digest",
            "is_executable",
            "isExecutable",
            "contents",
            "node_properties",
            "nodeProperties",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Path,
            Digest,
            IsExecutable,
            Contents,
            NodeProperties,
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
                            "path" => Ok(GeneratedField::Path),
                            "digest" => Ok(GeneratedField::Digest),
                            "isExecutable" | "is_executable" => Ok(GeneratedField::IsExecutable),
                            "contents" => Ok(GeneratedField::Contents),
                            "nodeProperties" | "node_properties" => Ok(GeneratedField::NodeProperties),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = OutputFile;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.OutputFile")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<OutputFile, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut path__ = None;
                let mut digest__ = None;
                let mut is_executable__ = None;
                let mut contents__ = None;
                let mut node_properties__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Path => {
                            if path__.is_some() {
                                return Err(serde::de::Error::duplicate_field("path"));
                            }
                            path__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Digest => {
                            if digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digest"));
                            }
                            digest__ = map_.next_value()?;
                        }
                        GeneratedField::IsExecutable => {
                            if is_executable__.is_some() {
                                return Err(serde::de::Error::duplicate_field("isExecutable"));
                            }
                            is_executable__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Contents => {
                            if contents__.is_some() {
                                return Err(serde::de::Error::duplicate_field("contents"));
                            }
                            contents__ = 
                                Some(map_.next_value::<::pbjson::private::BytesDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::NodeProperties => {
                            if node_properties__.is_some() {
                                return Err(serde::de::Error::duplicate_field("nodeProperties"));
                            }
                            node_properties__ = map_.next_value()?;
                        }
                    }
                }
                Ok(OutputFile {
                    path: path__.unwrap_or_default(),
                    digest: digest__,
                    is_executable: is_executable__.unwrap_or_default(),
                    contents: contents__.unwrap_or_default(),
                    node_properties: node_properties__,
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.OutputFile", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for OutputSymlink {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.path.is_empty() {
            len += 1;
        }
        if !self.target.is_empty() {
            len += 1;
        }
        if self.node_properties.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.OutputSymlink", len)?;
        if !self.path.is_empty() {
            struct_ser.serialize_field("path", &self.path)?;
        }
        if !self.target.is_empty() {
            struct_ser.serialize_field("target", &self.target)?;
        }
        if let Some(v) = self.node_properties.as_ref() {
            struct_ser.serialize_field("nodeProperties", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for OutputSymlink {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "path",
            "target",
            "node_properties",
            "nodeProperties",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Path,
            Target,
            NodeProperties,
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
                            "path" => Ok(GeneratedField::Path),
                            "target" => Ok(GeneratedField::Target),
                            "nodeProperties" | "node_properties" => Ok(GeneratedField::NodeProperties),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = OutputSymlink;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.OutputSymlink")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<OutputSymlink, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut path__ = None;
                let mut target__ = None;
                let mut node_properties__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Path => {
                            if path__.is_some() {
                                return Err(serde::de::Error::duplicate_field("path"));
                            }
                            path__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Target => {
                            if target__.is_some() {
                                return Err(serde::de::Error::duplicate_field("target"));
                            }
                            target__ = Some(map_.next_value()?);
                        }
                        GeneratedField::NodeProperties => {
                            if node_properties__.is_some() {
                                return Err(serde::de::Error::duplicate_field("nodeProperties"));
                            }
                            node_properties__ = map_.next_value()?;
                        }
                    }
                }
                Ok(OutputSymlink {
                    path: path__.unwrap_or_default(),
                    target: target__.unwrap_or_default(),
                    node_properties: node_properties__,
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.OutputSymlink", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for Platform {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.properties.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.Platform", len)?;
        if !self.properties.is_empty() {
            struct_ser.serialize_field("properties", &self.properties)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for Platform {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "properties",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Properties,
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
                            "properties" => Ok(GeneratedField::Properties),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = Platform;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.Platform")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<Platform, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut properties__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Properties => {
                            if properties__.is_some() {
                                return Err(serde::de::Error::duplicate_field("properties"));
                            }
                            properties__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(Platform {
                    properties: properties__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.Platform", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for platform::Property {
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
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.Platform.Property", len)?;
        if !self.name.is_empty() {
            struct_ser.serialize_field("name", &self.name)?;
        }
        if !self.value.is_empty() {
            struct_ser.serialize_field("value", &self.value)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for platform::Property {
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
            type Value = platform::Property;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.Platform.Property")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<platform::Property, V::Error>
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
                Ok(platform::Property {
                    name: name__.unwrap_or_default(),
                    value: value__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.Platform.Property", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for PriorityCapabilities {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.priorities.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.PriorityCapabilities", len)?;
        if !self.priorities.is_empty() {
            struct_ser.serialize_field("priorities", &self.priorities)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for PriorityCapabilities {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "priorities",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Priorities,
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
                            "priorities" => Ok(GeneratedField::Priorities),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = PriorityCapabilities;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.PriorityCapabilities")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<PriorityCapabilities, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut priorities__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Priorities => {
                            if priorities__.is_some() {
                                return Err(serde::de::Error::duplicate_field("priorities"));
                            }
                            priorities__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(PriorityCapabilities {
                    priorities: priorities__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.PriorityCapabilities", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for priority_capabilities::PriorityRange {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.min_priority != 0 {
            len += 1;
        }
        if self.max_priority != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.PriorityCapabilities.PriorityRange", len)?;
        if self.min_priority != 0 {
            struct_ser.serialize_field("minPriority", &self.min_priority)?;
        }
        if self.max_priority != 0 {
            struct_ser.serialize_field("maxPriority", &self.max_priority)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for priority_capabilities::PriorityRange {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "min_priority",
            "minPriority",
            "max_priority",
            "maxPriority",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            MinPriority,
            MaxPriority,
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
                            "minPriority" | "min_priority" => Ok(GeneratedField::MinPriority),
                            "maxPriority" | "max_priority" => Ok(GeneratedField::MaxPriority),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = priority_capabilities::PriorityRange;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.PriorityCapabilities.PriorityRange")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<priority_capabilities::PriorityRange, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut min_priority__ = None;
                let mut max_priority__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::MinPriority => {
                            if min_priority__.is_some() {
                                return Err(serde::de::Error::duplicate_field("minPriority"));
                            }
                            min_priority__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::MaxPriority => {
                            if max_priority__.is_some() {
                                return Err(serde::de::Error::duplicate_field("maxPriority"));
                            }
                            max_priority__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                    }
                }
                Ok(priority_capabilities::PriorityRange {
                    min_priority: min_priority__.unwrap_or_default(),
                    max_priority: max_priority__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.PriorityCapabilities.PriorityRange", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for RepMaxCdcParams {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.min_chunk_size_bytes != 0 {
            len += 1;
        }
        if self.horizon_size_bytes != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.RepMaxCdcParams", len)?;
        if self.min_chunk_size_bytes != 0 {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("minChunkSizeBytes", ToString::to_string(&self.min_chunk_size_bytes).as_str())?;
        }
        if self.horizon_size_bytes != 0 {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("horizonSizeBytes", ToString::to_string(&self.horizon_size_bytes).as_str())?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for RepMaxCdcParams {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "min_chunk_size_bytes",
            "minChunkSizeBytes",
            "horizon_size_bytes",
            "horizonSizeBytes",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            MinChunkSizeBytes,
            HorizonSizeBytes,
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
                            "minChunkSizeBytes" | "min_chunk_size_bytes" => Ok(GeneratedField::MinChunkSizeBytes),
                            "horizonSizeBytes" | "horizon_size_bytes" => Ok(GeneratedField::HorizonSizeBytes),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = RepMaxCdcParams;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.RepMaxCdcParams")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<RepMaxCdcParams, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut min_chunk_size_bytes__ = None;
                let mut horizon_size_bytes__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::MinChunkSizeBytes => {
                            if min_chunk_size_bytes__.is_some() {
                                return Err(serde::de::Error::duplicate_field("minChunkSizeBytes"));
                            }
                            min_chunk_size_bytes__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::HorizonSizeBytes => {
                            if horizon_size_bytes__.is_some() {
                                return Err(serde::de::Error::duplicate_field("horizonSizeBytes"));
                            }
                            horizon_size_bytes__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                    }
                }
                Ok(RepMaxCdcParams {
                    min_chunk_size_bytes: min_chunk_size_bytes__.unwrap_or_default(),
                    horizon_size_bytes: horizon_size_bytes__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.RepMaxCdcParams", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for RequestMetadata {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.tool_details.is_some() {
            len += 1;
        }
        if !self.action_id.is_empty() {
            len += 1;
        }
        if !self.tool_invocation_id.is_empty() {
            len += 1;
        }
        if !self.correlated_invocations_id.is_empty() {
            len += 1;
        }
        if !self.action_mnemonic.is_empty() {
            len += 1;
        }
        if !self.target_id.is_empty() {
            len += 1;
        }
        if !self.configuration_id.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.RequestMetadata", len)?;
        if let Some(v) = self.tool_details.as_ref() {
            struct_ser.serialize_field("toolDetails", v)?;
        }
        if !self.action_id.is_empty() {
            struct_ser.serialize_field("actionId", &self.action_id)?;
        }
        if !self.tool_invocation_id.is_empty() {
            struct_ser.serialize_field("toolInvocationId", &self.tool_invocation_id)?;
        }
        if !self.correlated_invocations_id.is_empty() {
            struct_ser.serialize_field("correlatedInvocationsId", &self.correlated_invocations_id)?;
        }
        if !self.action_mnemonic.is_empty() {
            struct_ser.serialize_field("actionMnemonic", &self.action_mnemonic)?;
        }
        if !self.target_id.is_empty() {
            struct_ser.serialize_field("targetId", &self.target_id)?;
        }
        if !self.configuration_id.is_empty() {
            struct_ser.serialize_field("configurationId", &self.configuration_id)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for RequestMetadata {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "tool_details",
            "toolDetails",
            "action_id",
            "actionId",
            "tool_invocation_id",
            "toolInvocationId",
            "correlated_invocations_id",
            "correlatedInvocationsId",
            "action_mnemonic",
            "actionMnemonic",
            "target_id",
            "targetId",
            "configuration_id",
            "configurationId",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            ToolDetails,
            ActionId,
            ToolInvocationId,
            CorrelatedInvocationsId,
            ActionMnemonic,
            TargetId,
            ConfigurationId,
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
                            "toolDetails" | "tool_details" => Ok(GeneratedField::ToolDetails),
                            "actionId" | "action_id" => Ok(GeneratedField::ActionId),
                            "toolInvocationId" | "tool_invocation_id" => Ok(GeneratedField::ToolInvocationId),
                            "correlatedInvocationsId" | "correlated_invocations_id" => Ok(GeneratedField::CorrelatedInvocationsId),
                            "actionMnemonic" | "action_mnemonic" => Ok(GeneratedField::ActionMnemonic),
                            "targetId" | "target_id" => Ok(GeneratedField::TargetId),
                            "configurationId" | "configuration_id" => Ok(GeneratedField::ConfigurationId),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = RequestMetadata;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.RequestMetadata")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<RequestMetadata, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut tool_details__ = None;
                let mut action_id__ = None;
                let mut tool_invocation_id__ = None;
                let mut correlated_invocations_id__ = None;
                let mut action_mnemonic__ = None;
                let mut target_id__ = None;
                let mut configuration_id__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::ToolDetails => {
                            if tool_details__.is_some() {
                                return Err(serde::de::Error::duplicate_field("toolDetails"));
                            }
                            tool_details__ = map_.next_value()?;
                        }
                        GeneratedField::ActionId => {
                            if action_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("actionId"));
                            }
                            action_id__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ToolInvocationId => {
                            if tool_invocation_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("toolInvocationId"));
                            }
                            tool_invocation_id__ = Some(map_.next_value()?);
                        }
                        GeneratedField::CorrelatedInvocationsId => {
                            if correlated_invocations_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("correlatedInvocationsId"));
                            }
                            correlated_invocations_id__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ActionMnemonic => {
                            if action_mnemonic__.is_some() {
                                return Err(serde::de::Error::duplicate_field("actionMnemonic"));
                            }
                            action_mnemonic__ = Some(map_.next_value()?);
                        }
                        GeneratedField::TargetId => {
                            if target_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("targetId"));
                            }
                            target_id__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ConfigurationId => {
                            if configuration_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("configurationId"));
                            }
                            configuration_id__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(RequestMetadata {
                    tool_details: tool_details__,
                    action_id: action_id__.unwrap_or_default(),
                    tool_invocation_id: tool_invocation_id__.unwrap_or_default(),
                    correlated_invocations_id: correlated_invocations_id__.unwrap_or_default(),
                    action_mnemonic: action_mnemonic__.unwrap_or_default(),
                    target_id: target_id__.unwrap_or_default(),
                    configuration_id: configuration_id__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.RequestMetadata", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ResultsCachePolicy {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.priority != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.ResultsCachePolicy", len)?;
        if self.priority != 0 {
            struct_ser.serialize_field("priority", &self.priority)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ResultsCachePolicy {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "priority",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Priority,
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
                            "priority" => Ok(GeneratedField::Priority),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ResultsCachePolicy;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.ResultsCachePolicy")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ResultsCachePolicy, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut priority__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Priority => {
                            if priority__.is_some() {
                                return Err(serde::de::Error::duplicate_field("priority"));
                            }
                            priority__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                    }
                }
                Ok(ResultsCachePolicy {
                    priority: priority__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.ResultsCachePolicy", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ServerCapabilities {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.cache_capabilities.is_some() {
            len += 1;
        }
        if self.execution_capabilities.is_some() {
            len += 1;
        }
        if self.deprecated_api_version.is_some() {
            len += 1;
        }
        if self.low_api_version.is_some() {
            len += 1;
        }
        if self.high_api_version.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.ServerCapabilities", len)?;
        if let Some(v) = self.cache_capabilities.as_ref() {
            struct_ser.serialize_field("cacheCapabilities", v)?;
        }
        if let Some(v) = self.execution_capabilities.as_ref() {
            struct_ser.serialize_field("executionCapabilities", v)?;
        }
        if let Some(v) = self.deprecated_api_version.as_ref() {
            struct_ser.serialize_field("deprecatedApiVersion", v)?;
        }
        if let Some(v) = self.low_api_version.as_ref() {
            struct_ser.serialize_field("lowApiVersion", v)?;
        }
        if let Some(v) = self.high_api_version.as_ref() {
            struct_ser.serialize_field("highApiVersion", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ServerCapabilities {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "cache_capabilities",
            "cacheCapabilities",
            "execution_capabilities",
            "executionCapabilities",
            "deprecated_api_version",
            "deprecatedApiVersion",
            "low_api_version",
            "lowApiVersion",
            "high_api_version",
            "highApiVersion",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            CacheCapabilities,
            ExecutionCapabilities,
            DeprecatedApiVersion,
            LowApiVersion,
            HighApiVersion,
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
                            "cacheCapabilities" | "cache_capabilities" => Ok(GeneratedField::CacheCapabilities),
                            "executionCapabilities" | "execution_capabilities" => Ok(GeneratedField::ExecutionCapabilities),
                            "deprecatedApiVersion" | "deprecated_api_version" => Ok(GeneratedField::DeprecatedApiVersion),
                            "lowApiVersion" | "low_api_version" => Ok(GeneratedField::LowApiVersion),
                            "highApiVersion" | "high_api_version" => Ok(GeneratedField::HighApiVersion),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ServerCapabilities;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.ServerCapabilities")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ServerCapabilities, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut cache_capabilities__ = None;
                let mut execution_capabilities__ = None;
                let mut deprecated_api_version__ = None;
                let mut low_api_version__ = None;
                let mut high_api_version__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::CacheCapabilities => {
                            if cache_capabilities__.is_some() {
                                return Err(serde::de::Error::duplicate_field("cacheCapabilities"));
                            }
                            cache_capabilities__ = map_.next_value()?;
                        }
                        GeneratedField::ExecutionCapabilities => {
                            if execution_capabilities__.is_some() {
                                return Err(serde::de::Error::duplicate_field("executionCapabilities"));
                            }
                            execution_capabilities__ = map_.next_value()?;
                        }
                        GeneratedField::DeprecatedApiVersion => {
                            if deprecated_api_version__.is_some() {
                                return Err(serde::de::Error::duplicate_field("deprecatedApiVersion"));
                            }
                            deprecated_api_version__ = map_.next_value()?;
                        }
                        GeneratedField::LowApiVersion => {
                            if low_api_version__.is_some() {
                                return Err(serde::de::Error::duplicate_field("lowApiVersion"));
                            }
                            low_api_version__ = map_.next_value()?;
                        }
                        GeneratedField::HighApiVersion => {
                            if high_api_version__.is_some() {
                                return Err(serde::de::Error::duplicate_field("highApiVersion"));
                            }
                            high_api_version__ = map_.next_value()?;
                        }
                    }
                }
                Ok(ServerCapabilities {
                    cache_capabilities: cache_capabilities__,
                    execution_capabilities: execution_capabilities__,
                    deprecated_api_version: deprecated_api_version__,
                    low_api_version: low_api_version__,
                    high_api_version: high_api_version__,
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.ServerCapabilities", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for SpliceBlobRequest {
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
        if self.blob_digest.is_some() {
            len += 1;
        }
        if !self.chunk_digests.is_empty() {
            len += 1;
        }
        if self.digest_function != 0 {
            len += 1;
        }
        if self.chunking_function != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.SpliceBlobRequest", len)?;
        if !self.instance_name.is_empty() {
            struct_ser.serialize_field("instanceName", &self.instance_name)?;
        }
        if let Some(v) = self.blob_digest.as_ref() {
            struct_ser.serialize_field("blobDigest", v)?;
        }
        if !self.chunk_digests.is_empty() {
            struct_ser.serialize_field("chunkDigests", &self.chunk_digests)?;
        }
        if self.digest_function != 0 {
            let v = digest_function::Value::try_from(self.digest_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.digest_function)))?;
            struct_ser.serialize_field("digestFunction", &v)?;
        }
        if self.chunking_function != 0 {
            let v = chunking_function::Value::try_from(self.chunking_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.chunking_function)))?;
            struct_ser.serialize_field("chunkingFunction", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for SpliceBlobRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "instance_name",
            "instanceName",
            "blob_digest",
            "blobDigest",
            "chunk_digests",
            "chunkDigests",
            "digest_function",
            "digestFunction",
            "chunking_function",
            "chunkingFunction",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            InstanceName,
            BlobDigest,
            ChunkDigests,
            DigestFunction,
            ChunkingFunction,
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
                            "blobDigest" | "blob_digest" => Ok(GeneratedField::BlobDigest),
                            "chunkDigests" | "chunk_digests" => Ok(GeneratedField::ChunkDigests),
                            "digestFunction" | "digest_function" => Ok(GeneratedField::DigestFunction),
                            "chunkingFunction" | "chunking_function" => Ok(GeneratedField::ChunkingFunction),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = SpliceBlobRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.SpliceBlobRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<SpliceBlobRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut instance_name__ = None;
                let mut blob_digest__ = None;
                let mut chunk_digests__ = None;
                let mut digest_function__ = None;
                let mut chunking_function__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::InstanceName => {
                            if instance_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("instanceName"));
                            }
                            instance_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::BlobDigest => {
                            if blob_digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("blobDigest"));
                            }
                            blob_digest__ = map_.next_value()?;
                        }
                        GeneratedField::ChunkDigests => {
                            if chunk_digests__.is_some() {
                                return Err(serde::de::Error::duplicate_field("chunkDigests"));
                            }
                            chunk_digests__ = Some(map_.next_value()?);
                        }
                        GeneratedField::DigestFunction => {
                            if digest_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digestFunction"));
                            }
                            digest_function__ = Some(map_.next_value::<digest_function::Value>()? as i32);
                        }
                        GeneratedField::ChunkingFunction => {
                            if chunking_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("chunkingFunction"));
                            }
                            chunking_function__ = Some(map_.next_value::<chunking_function::Value>()? as i32);
                        }
                    }
                }
                Ok(SpliceBlobRequest {
                    instance_name: instance_name__.unwrap_or_default(),
                    blob_digest: blob_digest__,
                    chunk_digests: chunk_digests__.unwrap_or_default(),
                    digest_function: digest_function__.unwrap_or_default(),
                    chunking_function: chunking_function__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.SpliceBlobRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for SpliceBlobResponse {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.blob_digest.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.SpliceBlobResponse", len)?;
        if let Some(v) = self.blob_digest.as_ref() {
            struct_ser.serialize_field("blobDigest", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for SpliceBlobResponse {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "blob_digest",
            "blobDigest",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            BlobDigest,
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
                            "blobDigest" | "blob_digest" => Ok(GeneratedField::BlobDigest),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = SpliceBlobResponse;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.SpliceBlobResponse")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<SpliceBlobResponse, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut blob_digest__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::BlobDigest => {
                            if blob_digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("blobDigest"));
                            }
                            blob_digest__ = map_.next_value()?;
                        }
                    }
                }
                Ok(SpliceBlobResponse {
                    blob_digest: blob_digest__,
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.SpliceBlobResponse", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for SplitBlobRequest {
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
        if self.blob_digest.is_some() {
            len += 1;
        }
        if self.digest_function != 0 {
            len += 1;
        }
        if self.chunking_function != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.SplitBlobRequest", len)?;
        if !self.instance_name.is_empty() {
            struct_ser.serialize_field("instanceName", &self.instance_name)?;
        }
        if let Some(v) = self.blob_digest.as_ref() {
            struct_ser.serialize_field("blobDigest", v)?;
        }
        if self.digest_function != 0 {
            let v = digest_function::Value::try_from(self.digest_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.digest_function)))?;
            struct_ser.serialize_field("digestFunction", &v)?;
        }
        if self.chunking_function != 0 {
            let v = chunking_function::Value::try_from(self.chunking_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.chunking_function)))?;
            struct_ser.serialize_field("chunkingFunction", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for SplitBlobRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "instance_name",
            "instanceName",
            "blob_digest",
            "blobDigest",
            "digest_function",
            "digestFunction",
            "chunking_function",
            "chunkingFunction",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            InstanceName,
            BlobDigest,
            DigestFunction,
            ChunkingFunction,
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
                            "blobDigest" | "blob_digest" => Ok(GeneratedField::BlobDigest),
                            "digestFunction" | "digest_function" => Ok(GeneratedField::DigestFunction),
                            "chunkingFunction" | "chunking_function" => Ok(GeneratedField::ChunkingFunction),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = SplitBlobRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.SplitBlobRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<SplitBlobRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut instance_name__ = None;
                let mut blob_digest__ = None;
                let mut digest_function__ = None;
                let mut chunking_function__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::InstanceName => {
                            if instance_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("instanceName"));
                            }
                            instance_name__ = Some(map_.next_value()?);
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
                            digest_function__ = Some(map_.next_value::<digest_function::Value>()? as i32);
                        }
                        GeneratedField::ChunkingFunction => {
                            if chunking_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("chunkingFunction"));
                            }
                            chunking_function__ = Some(map_.next_value::<chunking_function::Value>()? as i32);
                        }
                    }
                }
                Ok(SplitBlobRequest {
                    instance_name: instance_name__.unwrap_or_default(),
                    blob_digest: blob_digest__,
                    digest_function: digest_function__.unwrap_or_default(),
                    chunking_function: chunking_function__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.SplitBlobRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for SplitBlobResponse {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.chunk_digests.is_empty() {
            len += 1;
        }
        if self.chunking_function != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.SplitBlobResponse", len)?;
        if !self.chunk_digests.is_empty() {
            struct_ser.serialize_field("chunkDigests", &self.chunk_digests)?;
        }
        if self.chunking_function != 0 {
            let v = chunking_function::Value::try_from(self.chunking_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.chunking_function)))?;
            struct_ser.serialize_field("chunkingFunction", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for SplitBlobResponse {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "chunk_digests",
            "chunkDigests",
            "chunking_function",
            "chunkingFunction",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            ChunkDigests,
            ChunkingFunction,
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
                            "chunkDigests" | "chunk_digests" => Ok(GeneratedField::ChunkDigests),
                            "chunkingFunction" | "chunking_function" => Ok(GeneratedField::ChunkingFunction),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = SplitBlobResponse;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.SplitBlobResponse")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<SplitBlobResponse, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut chunk_digests__ = None;
                let mut chunking_function__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::ChunkDigests => {
                            if chunk_digests__.is_some() {
                                return Err(serde::de::Error::duplicate_field("chunkDigests"));
                            }
                            chunk_digests__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ChunkingFunction => {
                            if chunking_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("chunkingFunction"));
                            }
                            chunking_function__ = Some(map_.next_value::<chunking_function::Value>()? as i32);
                        }
                    }
                }
                Ok(SplitBlobResponse {
                    chunk_digests: chunk_digests__.unwrap_or_default(),
                    chunking_function: chunking_function__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.SplitBlobResponse", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for SymlinkAbsolutePathStrategy {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let len = 0;
        let struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.SymlinkAbsolutePathStrategy", len)?;
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for SymlinkAbsolutePathStrategy {
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
            type Value = SymlinkAbsolutePathStrategy;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.SymlinkAbsolutePathStrategy")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<SymlinkAbsolutePathStrategy, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                while map_.next_key::<GeneratedField>()?.is_some() {
                    let _ = map_.next_value::<serde::de::IgnoredAny>()?;
                }
                Ok(SymlinkAbsolutePathStrategy {
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.SymlinkAbsolutePathStrategy", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for symlink_absolute_path_strategy::Value {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let variant = match self {
            Self::Unknown => "UNKNOWN",
            Self::Disallowed => "DISALLOWED",
            Self::Allowed => "ALLOWED",
        };
        serializer.serialize_str(variant)
    }
}
impl<'de> serde::Deserialize<'de> for symlink_absolute_path_strategy::Value {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "UNKNOWN",
            "DISALLOWED",
            "ALLOWED",
        ];

        struct GeneratedVisitor;

        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = symlink_absolute_path_strategy::Value;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                write!(formatter, "expected one of: {:?}", &FIELDS)
            }

            fn visit_i64<E>(self, v: i64) -> std::result::Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                i32::try_from(v)
                    .ok()
                    .and_then(|x| x.try_into().ok())
                    .ok_or_else(|| {
                        serde::de::Error::invalid_value(serde::de::Unexpected::Signed(v), &self)
                    })
            }

            fn visit_u64<E>(self, v: u64) -> std::result::Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                i32::try_from(v)
                    .ok()
                    .and_then(|x| x.try_into().ok())
                    .ok_or_else(|| {
                        serde::de::Error::invalid_value(serde::de::Unexpected::Unsigned(v), &self)
                    })
            }

            fn visit_str<E>(self, value: &str) -> std::result::Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                match value {
                    "UNKNOWN" => Ok(symlink_absolute_path_strategy::Value::Unknown),
                    "DISALLOWED" => Ok(symlink_absolute_path_strategy::Value::Disallowed),
                    "ALLOWED" => Ok(symlink_absolute_path_strategy::Value::Allowed),
                    _ => Err(serde::de::Error::unknown_variant(value, FIELDS)),
                }
            }
        }
        deserializer.deserialize_any(GeneratedVisitor)
    }
}
impl serde::Serialize for SymlinkNode {
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
        if !self.target.is_empty() {
            len += 1;
        }
        if self.node_properties.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.SymlinkNode", len)?;
        if !self.name.is_empty() {
            struct_ser.serialize_field("name", &self.name)?;
        }
        if !self.target.is_empty() {
            struct_ser.serialize_field("target", &self.target)?;
        }
        if let Some(v) = self.node_properties.as_ref() {
            struct_ser.serialize_field("nodeProperties", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for SymlinkNode {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "name",
            "target",
            "node_properties",
            "nodeProperties",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Name,
            Target,
            NodeProperties,
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
                            "target" => Ok(GeneratedField::Target),
                            "nodeProperties" | "node_properties" => Ok(GeneratedField::NodeProperties),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = SymlinkNode;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.SymlinkNode")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<SymlinkNode, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut name__ = None;
                let mut target__ = None;
                let mut node_properties__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Name => {
                            if name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("name"));
                            }
                            name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Target => {
                            if target__.is_some() {
                                return Err(serde::de::Error::duplicate_field("target"));
                            }
                            target__ = Some(map_.next_value()?);
                        }
                        GeneratedField::NodeProperties => {
                            if node_properties__.is_some() {
                                return Err(serde::de::Error::duplicate_field("nodeProperties"));
                            }
                            node_properties__ = map_.next_value()?;
                        }
                    }
                }
                Ok(SymlinkNode {
                    name: name__.unwrap_or_default(),
                    target: target__.unwrap_or_default(),
                    node_properties: node_properties__,
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.SymlinkNode", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ToolDetails {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.tool_name.is_empty() {
            len += 1;
        }
        if !self.tool_version.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.ToolDetails", len)?;
        if !self.tool_name.is_empty() {
            struct_ser.serialize_field("toolName", &self.tool_name)?;
        }
        if !self.tool_version.is_empty() {
            struct_ser.serialize_field("toolVersion", &self.tool_version)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ToolDetails {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "tool_name",
            "toolName",
            "tool_version",
            "toolVersion",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            ToolName,
            ToolVersion,
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
                            "toolName" | "tool_name" => Ok(GeneratedField::ToolName),
                            "toolVersion" | "tool_version" => Ok(GeneratedField::ToolVersion),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ToolDetails;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.ToolDetails")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ToolDetails, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut tool_name__ = None;
                let mut tool_version__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::ToolName => {
                            if tool_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("toolName"));
                            }
                            tool_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ToolVersion => {
                            if tool_version__.is_some() {
                                return Err(serde::de::Error::duplicate_field("toolVersion"));
                            }
                            tool_version__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(ToolDetails {
                    tool_name: tool_name__.unwrap_or_default(),
                    tool_version: tool_version__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.ToolDetails", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for Tree {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.root.is_some() {
            len += 1;
        }
        if !self.children.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.Tree", len)?;
        if let Some(v) = self.root.as_ref() {
            struct_ser.serialize_field("root", v)?;
        }
        if !self.children.is_empty() {
            struct_ser.serialize_field("children", &self.children)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for Tree {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "root",
            "children",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Root,
            Children,
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
                            "root" => Ok(GeneratedField::Root),
                            "children" => Ok(GeneratedField::Children),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = Tree;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.Tree")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<Tree, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut root__ = None;
                let mut children__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Root => {
                            if root__.is_some() {
                                return Err(serde::de::Error::duplicate_field("root"));
                            }
                            root__ = map_.next_value()?;
                        }
                        GeneratedField::Children => {
                            if children__.is_some() {
                                return Err(serde::de::Error::duplicate_field("children"));
                            }
                            children__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(Tree {
                    root: root__,
                    children: children__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.Tree", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for UpdateActionResultRequest {
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
        if self.action_digest.is_some() {
            len += 1;
        }
        if self.action_result.is_some() {
            len += 1;
        }
        if self.results_cache_policy.is_some() {
            len += 1;
        }
        if self.digest_function != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.UpdateActionResultRequest", len)?;
        if !self.instance_name.is_empty() {
            struct_ser.serialize_field("instanceName", &self.instance_name)?;
        }
        if let Some(v) = self.action_digest.as_ref() {
            struct_ser.serialize_field("actionDigest", v)?;
        }
        if let Some(v) = self.action_result.as_ref() {
            struct_ser.serialize_field("actionResult", v)?;
        }
        if let Some(v) = self.results_cache_policy.as_ref() {
            struct_ser.serialize_field("resultsCachePolicy", v)?;
        }
        if self.digest_function != 0 {
            let v = digest_function::Value::try_from(self.digest_function)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.digest_function)))?;
            struct_ser.serialize_field("digestFunction", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for UpdateActionResultRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "instance_name",
            "instanceName",
            "action_digest",
            "actionDigest",
            "action_result",
            "actionResult",
            "results_cache_policy",
            "resultsCachePolicy",
            "digest_function",
            "digestFunction",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            InstanceName,
            ActionDigest,
            ActionResult,
            ResultsCachePolicy,
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
                            "actionDigest" | "action_digest" => Ok(GeneratedField::ActionDigest),
                            "actionResult" | "action_result" => Ok(GeneratedField::ActionResult),
                            "resultsCachePolicy" | "results_cache_policy" => Ok(GeneratedField::ResultsCachePolicy),
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
            type Value = UpdateActionResultRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.UpdateActionResultRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<UpdateActionResultRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut instance_name__ = None;
                let mut action_digest__ = None;
                let mut action_result__ = None;
                let mut results_cache_policy__ = None;
                let mut digest_function__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::InstanceName => {
                            if instance_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("instanceName"));
                            }
                            instance_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ActionDigest => {
                            if action_digest__.is_some() {
                                return Err(serde::de::Error::duplicate_field("actionDigest"));
                            }
                            action_digest__ = map_.next_value()?;
                        }
                        GeneratedField::ActionResult => {
                            if action_result__.is_some() {
                                return Err(serde::de::Error::duplicate_field("actionResult"));
                            }
                            action_result__ = map_.next_value()?;
                        }
                        GeneratedField::ResultsCachePolicy => {
                            if results_cache_policy__.is_some() {
                                return Err(serde::de::Error::duplicate_field("resultsCachePolicy"));
                            }
                            results_cache_policy__ = map_.next_value()?;
                        }
                        GeneratedField::DigestFunction => {
                            if digest_function__.is_some() {
                                return Err(serde::de::Error::duplicate_field("digestFunction"));
                            }
                            digest_function__ = Some(map_.next_value::<digest_function::Value>()? as i32);
                        }
                    }
                }
                Ok(UpdateActionResultRequest {
                    instance_name: instance_name__.unwrap_or_default(),
                    action_digest: action_digest__,
                    action_result: action_result__,
                    results_cache_policy: results_cache_policy__,
                    digest_function: digest_function__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.UpdateActionResultRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for WaitExecutionRequest {
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
        let mut struct_ser = serializer.serialize_struct("build.bazel.remote.execution.v2.WaitExecutionRequest", len)?;
        if !self.name.is_empty() {
            struct_ser.serialize_field("name", &self.name)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for WaitExecutionRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "name",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Name,
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
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = WaitExecutionRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.remote.execution.v2.WaitExecutionRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<WaitExecutionRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut name__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Name => {
                            if name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("name"));
                            }
                            name__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(WaitExecutionRequest {
                    name: name__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.remote.execution.v2.WaitExecutionRequest", FIELDS, GeneratedVisitor)
    }
}
