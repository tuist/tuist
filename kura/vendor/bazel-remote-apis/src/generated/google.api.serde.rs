impl serde::Serialize for BatchingConfigProto {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.thresholds.is_some() {
            len += 1;
        }
        if self.batch_descriptor.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.BatchingConfigProto", len)?;
        if let Some(v) = self.thresholds.as_ref() {
            struct_ser.serialize_field("thresholds", v)?;
        }
        if let Some(v) = self.batch_descriptor.as_ref() {
            struct_ser.serialize_field("batchDescriptor", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for BatchingConfigProto {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "thresholds",
            "batch_descriptor",
            "batchDescriptor",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Thresholds,
            BatchDescriptor,
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
                            "thresholds" => Ok(GeneratedField::Thresholds),
                            "batchDescriptor" | "batch_descriptor" => Ok(GeneratedField::BatchDescriptor),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = BatchingConfigProto;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.BatchingConfigProto")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<BatchingConfigProto, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut thresholds__ = None;
                let mut batch_descriptor__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Thresholds => {
                            if thresholds__.is_some() {
                                return Err(serde::de::Error::duplicate_field("thresholds"));
                            }
                            thresholds__ = map_.next_value()?;
                        }
                        GeneratedField::BatchDescriptor => {
                            if batch_descriptor__.is_some() {
                                return Err(serde::de::Error::duplicate_field("batchDescriptor"));
                            }
                            batch_descriptor__ = map_.next_value()?;
                        }
                    }
                }
                Ok(BatchingConfigProto {
                    thresholds: thresholds__,
                    batch_descriptor: batch_descriptor__,
                })
            }
        }
        deserializer.deserialize_struct("google.api.BatchingConfigProto", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for BatchingDescriptorProto {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.batched_field.is_empty() {
            len += 1;
        }
        if !self.discriminator_fields.is_empty() {
            len += 1;
        }
        if !self.subresponse_field.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.BatchingDescriptorProto", len)?;
        if !self.batched_field.is_empty() {
            struct_ser.serialize_field("batchedField", &self.batched_field)?;
        }
        if !self.discriminator_fields.is_empty() {
            struct_ser.serialize_field("discriminatorFields", &self.discriminator_fields)?;
        }
        if !self.subresponse_field.is_empty() {
            struct_ser.serialize_field("subresponseField", &self.subresponse_field)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for BatchingDescriptorProto {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "batched_field",
            "batchedField",
            "discriminator_fields",
            "discriminatorFields",
            "subresponse_field",
            "subresponseField",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            BatchedField,
            DiscriminatorFields,
            SubresponseField,
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
                            "batchedField" | "batched_field" => Ok(GeneratedField::BatchedField),
                            "discriminatorFields" | "discriminator_fields" => Ok(GeneratedField::DiscriminatorFields),
                            "subresponseField" | "subresponse_field" => Ok(GeneratedField::SubresponseField),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = BatchingDescriptorProto;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.BatchingDescriptorProto")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<BatchingDescriptorProto, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut batched_field__ = None;
                let mut discriminator_fields__ = None;
                let mut subresponse_field__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::BatchedField => {
                            if batched_field__.is_some() {
                                return Err(serde::de::Error::duplicate_field("batchedField"));
                            }
                            batched_field__ = Some(map_.next_value()?);
                        }
                        GeneratedField::DiscriminatorFields => {
                            if discriminator_fields__.is_some() {
                                return Err(serde::de::Error::duplicate_field("discriminatorFields"));
                            }
                            discriminator_fields__ = Some(map_.next_value()?);
                        }
                        GeneratedField::SubresponseField => {
                            if subresponse_field__.is_some() {
                                return Err(serde::de::Error::duplicate_field("subresponseField"));
                            }
                            subresponse_field__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(BatchingDescriptorProto {
                    batched_field: batched_field__.unwrap_or_default(),
                    discriminator_fields: discriminator_fields__.unwrap_or_default(),
                    subresponse_field: subresponse_field__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("google.api.BatchingDescriptorProto", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for BatchingSettingsProto {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.element_count_threshold != 0 {
            len += 1;
        }
        if self.request_byte_threshold != 0 {
            len += 1;
        }
        if self.delay_threshold.is_some() {
            len += 1;
        }
        if self.element_count_limit != 0 {
            len += 1;
        }
        if self.request_byte_limit != 0 {
            len += 1;
        }
        if self.flow_control_element_limit != 0 {
            len += 1;
        }
        if self.flow_control_byte_limit != 0 {
            len += 1;
        }
        if self.flow_control_limit_exceeded_behavior != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.BatchingSettingsProto", len)?;
        if self.element_count_threshold != 0 {
            struct_ser.serialize_field("elementCountThreshold", &self.element_count_threshold)?;
        }
        if self.request_byte_threshold != 0 {
            #[allow(clippy::needless_borrow)]
            #[allow(clippy::needless_borrows_for_generic_args)]
            struct_ser.serialize_field("requestByteThreshold", ToString::to_string(&self.request_byte_threshold).as_str())?;
        }
        if let Some(v) = self.delay_threshold.as_ref() {
            struct_ser.serialize_field("delayThreshold", v)?;
        }
        if self.element_count_limit != 0 {
            struct_ser.serialize_field("elementCountLimit", &self.element_count_limit)?;
        }
        if self.request_byte_limit != 0 {
            struct_ser.serialize_field("requestByteLimit", &self.request_byte_limit)?;
        }
        if self.flow_control_element_limit != 0 {
            struct_ser.serialize_field("flowControlElementLimit", &self.flow_control_element_limit)?;
        }
        if self.flow_control_byte_limit != 0 {
            struct_ser.serialize_field("flowControlByteLimit", &self.flow_control_byte_limit)?;
        }
        if self.flow_control_limit_exceeded_behavior != 0 {
            let v = FlowControlLimitExceededBehaviorProto::try_from(self.flow_control_limit_exceeded_behavior)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.flow_control_limit_exceeded_behavior)))?;
            struct_ser.serialize_field("flowControlLimitExceededBehavior", &v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for BatchingSettingsProto {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "element_count_threshold",
            "elementCountThreshold",
            "request_byte_threshold",
            "requestByteThreshold",
            "delay_threshold",
            "delayThreshold",
            "element_count_limit",
            "elementCountLimit",
            "request_byte_limit",
            "requestByteLimit",
            "flow_control_element_limit",
            "flowControlElementLimit",
            "flow_control_byte_limit",
            "flowControlByteLimit",
            "flow_control_limit_exceeded_behavior",
            "flowControlLimitExceededBehavior",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            ElementCountThreshold,
            RequestByteThreshold,
            DelayThreshold,
            ElementCountLimit,
            RequestByteLimit,
            FlowControlElementLimit,
            FlowControlByteLimit,
            FlowControlLimitExceededBehavior,
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
                            "elementCountThreshold" | "element_count_threshold" => Ok(GeneratedField::ElementCountThreshold),
                            "requestByteThreshold" | "request_byte_threshold" => Ok(GeneratedField::RequestByteThreshold),
                            "delayThreshold" | "delay_threshold" => Ok(GeneratedField::DelayThreshold),
                            "elementCountLimit" | "element_count_limit" => Ok(GeneratedField::ElementCountLimit),
                            "requestByteLimit" | "request_byte_limit" => Ok(GeneratedField::RequestByteLimit),
                            "flowControlElementLimit" | "flow_control_element_limit" => Ok(GeneratedField::FlowControlElementLimit),
                            "flowControlByteLimit" | "flow_control_byte_limit" => Ok(GeneratedField::FlowControlByteLimit),
                            "flowControlLimitExceededBehavior" | "flow_control_limit_exceeded_behavior" => Ok(GeneratedField::FlowControlLimitExceededBehavior),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = BatchingSettingsProto;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.BatchingSettingsProto")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<BatchingSettingsProto, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut element_count_threshold__ = None;
                let mut request_byte_threshold__ = None;
                let mut delay_threshold__ = None;
                let mut element_count_limit__ = None;
                let mut request_byte_limit__ = None;
                let mut flow_control_element_limit__ = None;
                let mut flow_control_byte_limit__ = None;
                let mut flow_control_limit_exceeded_behavior__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::ElementCountThreshold => {
                            if element_count_threshold__.is_some() {
                                return Err(serde::de::Error::duplicate_field("elementCountThreshold"));
                            }
                            element_count_threshold__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::RequestByteThreshold => {
                            if request_byte_threshold__.is_some() {
                                return Err(serde::de::Error::duplicate_field("requestByteThreshold"));
                            }
                            request_byte_threshold__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::DelayThreshold => {
                            if delay_threshold__.is_some() {
                                return Err(serde::de::Error::duplicate_field("delayThreshold"));
                            }
                            delay_threshold__ = map_.next_value()?;
                        }
                        GeneratedField::ElementCountLimit => {
                            if element_count_limit__.is_some() {
                                return Err(serde::de::Error::duplicate_field("elementCountLimit"));
                            }
                            element_count_limit__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::RequestByteLimit => {
                            if request_byte_limit__.is_some() {
                                return Err(serde::de::Error::duplicate_field("requestByteLimit"));
                            }
                            request_byte_limit__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::FlowControlElementLimit => {
                            if flow_control_element_limit__.is_some() {
                                return Err(serde::de::Error::duplicate_field("flowControlElementLimit"));
                            }
                            flow_control_element_limit__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::FlowControlByteLimit => {
                            if flow_control_byte_limit__.is_some() {
                                return Err(serde::de::Error::duplicate_field("flowControlByteLimit"));
                            }
                            flow_control_byte_limit__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::FlowControlLimitExceededBehavior => {
                            if flow_control_limit_exceeded_behavior__.is_some() {
                                return Err(serde::de::Error::duplicate_field("flowControlLimitExceededBehavior"));
                            }
                            flow_control_limit_exceeded_behavior__ = Some(map_.next_value::<FlowControlLimitExceededBehaviorProto>()? as i32);
                        }
                    }
                }
                Ok(BatchingSettingsProto {
                    element_count_threshold: element_count_threshold__.unwrap_or_default(),
                    request_byte_threshold: request_byte_threshold__.unwrap_or_default(),
                    delay_threshold: delay_threshold__,
                    element_count_limit: element_count_limit__.unwrap_or_default(),
                    request_byte_limit: request_byte_limit__.unwrap_or_default(),
                    flow_control_element_limit: flow_control_element_limit__.unwrap_or_default(),
                    flow_control_byte_limit: flow_control_byte_limit__.unwrap_or_default(),
                    flow_control_limit_exceeded_behavior: flow_control_limit_exceeded_behavior__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("google.api.BatchingSettingsProto", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ClientLibraryDestination {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let variant = match self {
            Self::Unspecified => "CLIENT_LIBRARY_DESTINATION_UNSPECIFIED",
            Self::Github => "GITHUB",
            Self::PackageManager => "PACKAGE_MANAGER",
        };
        serializer.serialize_str(variant)
    }
}
impl<'de> serde::Deserialize<'de> for ClientLibraryDestination {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "CLIENT_LIBRARY_DESTINATION_UNSPECIFIED",
            "GITHUB",
            "PACKAGE_MANAGER",
        ];

        struct GeneratedVisitor;

        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ClientLibraryDestination;

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
                    "CLIENT_LIBRARY_DESTINATION_UNSPECIFIED" => Ok(ClientLibraryDestination::Unspecified),
                    "GITHUB" => Ok(ClientLibraryDestination::Github),
                    "PACKAGE_MANAGER" => Ok(ClientLibraryDestination::PackageManager),
                    _ => Err(serde::de::Error::unknown_variant(value, FIELDS)),
                }
            }
        }
        deserializer.deserialize_any(GeneratedVisitor)
    }
}
impl serde::Serialize for ClientLibraryOrganization {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let variant = match self {
            Self::Unspecified => "CLIENT_LIBRARY_ORGANIZATION_UNSPECIFIED",
            Self::Cloud => "CLOUD",
            Self::Ads => "ADS",
            Self::Photos => "PHOTOS",
            Self::StreetView => "STREET_VIEW",
            Self::Shopping => "SHOPPING",
            Self::Geo => "GEO",
            Self::GenerativeAi => "GENERATIVE_AI",
        };
        serializer.serialize_str(variant)
    }
}
impl<'de> serde::Deserialize<'de> for ClientLibraryOrganization {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "CLIENT_LIBRARY_ORGANIZATION_UNSPECIFIED",
            "CLOUD",
            "ADS",
            "PHOTOS",
            "STREET_VIEW",
            "SHOPPING",
            "GEO",
            "GENERATIVE_AI",
        ];

        struct GeneratedVisitor;

        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ClientLibraryOrganization;

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
                    "CLIENT_LIBRARY_ORGANIZATION_UNSPECIFIED" => Ok(ClientLibraryOrganization::Unspecified),
                    "CLOUD" => Ok(ClientLibraryOrganization::Cloud),
                    "ADS" => Ok(ClientLibraryOrganization::Ads),
                    "PHOTOS" => Ok(ClientLibraryOrganization::Photos),
                    "STREET_VIEW" => Ok(ClientLibraryOrganization::StreetView),
                    "SHOPPING" => Ok(ClientLibraryOrganization::Shopping),
                    "GEO" => Ok(ClientLibraryOrganization::Geo),
                    "GENERATIVE_AI" => Ok(ClientLibraryOrganization::GenerativeAi),
                    _ => Err(serde::de::Error::unknown_variant(value, FIELDS)),
                }
            }
        }
        deserializer.deserialize_any(GeneratedVisitor)
    }
}
impl serde::Serialize for ClientLibrarySettings {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.version.is_empty() {
            len += 1;
        }
        if self.launch_stage != 0 {
            len += 1;
        }
        if self.rest_numeric_enums {
            len += 1;
        }
        if self.java_settings.is_some() {
            len += 1;
        }
        if self.cpp_settings.is_some() {
            len += 1;
        }
        if self.php_settings.is_some() {
            len += 1;
        }
        if self.python_settings.is_some() {
            len += 1;
        }
        if self.node_settings.is_some() {
            len += 1;
        }
        if self.dotnet_settings.is_some() {
            len += 1;
        }
        if self.ruby_settings.is_some() {
            len += 1;
        }
        if self.go_settings.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.ClientLibrarySettings", len)?;
        if !self.version.is_empty() {
            struct_ser.serialize_field("version", &self.version)?;
        }
        if self.launch_stage != 0 {
            let v = LaunchStage::try_from(self.launch_stage)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.launch_stage)))?;
            struct_ser.serialize_field("launchStage", &v)?;
        }
        if self.rest_numeric_enums {
            struct_ser.serialize_field("restNumericEnums", &self.rest_numeric_enums)?;
        }
        if let Some(v) = self.java_settings.as_ref() {
            struct_ser.serialize_field("javaSettings", v)?;
        }
        if let Some(v) = self.cpp_settings.as_ref() {
            struct_ser.serialize_field("cppSettings", v)?;
        }
        if let Some(v) = self.php_settings.as_ref() {
            struct_ser.serialize_field("phpSettings", v)?;
        }
        if let Some(v) = self.python_settings.as_ref() {
            struct_ser.serialize_field("pythonSettings", v)?;
        }
        if let Some(v) = self.node_settings.as_ref() {
            struct_ser.serialize_field("nodeSettings", v)?;
        }
        if let Some(v) = self.dotnet_settings.as_ref() {
            struct_ser.serialize_field("dotnetSettings", v)?;
        }
        if let Some(v) = self.ruby_settings.as_ref() {
            struct_ser.serialize_field("rubySettings", v)?;
        }
        if let Some(v) = self.go_settings.as_ref() {
            struct_ser.serialize_field("goSettings", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ClientLibrarySettings {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "version",
            "launch_stage",
            "launchStage",
            "rest_numeric_enums",
            "restNumericEnums",
            "java_settings",
            "javaSettings",
            "cpp_settings",
            "cppSettings",
            "php_settings",
            "phpSettings",
            "python_settings",
            "pythonSettings",
            "node_settings",
            "nodeSettings",
            "dotnet_settings",
            "dotnetSettings",
            "ruby_settings",
            "rubySettings",
            "go_settings",
            "goSettings",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Version,
            LaunchStage,
            RestNumericEnums,
            JavaSettings,
            CppSettings,
            PhpSettings,
            PythonSettings,
            NodeSettings,
            DotnetSettings,
            RubySettings,
            GoSettings,
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
                            "version" => Ok(GeneratedField::Version),
                            "launchStage" | "launch_stage" => Ok(GeneratedField::LaunchStage),
                            "restNumericEnums" | "rest_numeric_enums" => Ok(GeneratedField::RestNumericEnums),
                            "javaSettings" | "java_settings" => Ok(GeneratedField::JavaSettings),
                            "cppSettings" | "cpp_settings" => Ok(GeneratedField::CppSettings),
                            "phpSettings" | "php_settings" => Ok(GeneratedField::PhpSettings),
                            "pythonSettings" | "python_settings" => Ok(GeneratedField::PythonSettings),
                            "nodeSettings" | "node_settings" => Ok(GeneratedField::NodeSettings),
                            "dotnetSettings" | "dotnet_settings" => Ok(GeneratedField::DotnetSettings),
                            "rubySettings" | "ruby_settings" => Ok(GeneratedField::RubySettings),
                            "goSettings" | "go_settings" => Ok(GeneratedField::GoSettings),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ClientLibrarySettings;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.ClientLibrarySettings")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ClientLibrarySettings, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut version__ = None;
                let mut launch_stage__ = None;
                let mut rest_numeric_enums__ = None;
                let mut java_settings__ = None;
                let mut cpp_settings__ = None;
                let mut php_settings__ = None;
                let mut python_settings__ = None;
                let mut node_settings__ = None;
                let mut dotnet_settings__ = None;
                let mut ruby_settings__ = None;
                let mut go_settings__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Version => {
                            if version__.is_some() {
                                return Err(serde::de::Error::duplicate_field("version"));
                            }
                            version__ = Some(map_.next_value()?);
                        }
                        GeneratedField::LaunchStage => {
                            if launch_stage__.is_some() {
                                return Err(serde::de::Error::duplicate_field("launchStage"));
                            }
                            launch_stage__ = Some(map_.next_value::<LaunchStage>()? as i32);
                        }
                        GeneratedField::RestNumericEnums => {
                            if rest_numeric_enums__.is_some() {
                                return Err(serde::de::Error::duplicate_field("restNumericEnums"));
                            }
                            rest_numeric_enums__ = Some(map_.next_value()?);
                        }
                        GeneratedField::JavaSettings => {
                            if java_settings__.is_some() {
                                return Err(serde::de::Error::duplicate_field("javaSettings"));
                            }
                            java_settings__ = map_.next_value()?;
                        }
                        GeneratedField::CppSettings => {
                            if cpp_settings__.is_some() {
                                return Err(serde::de::Error::duplicate_field("cppSettings"));
                            }
                            cpp_settings__ = map_.next_value()?;
                        }
                        GeneratedField::PhpSettings => {
                            if php_settings__.is_some() {
                                return Err(serde::de::Error::duplicate_field("phpSettings"));
                            }
                            php_settings__ = map_.next_value()?;
                        }
                        GeneratedField::PythonSettings => {
                            if python_settings__.is_some() {
                                return Err(serde::de::Error::duplicate_field("pythonSettings"));
                            }
                            python_settings__ = map_.next_value()?;
                        }
                        GeneratedField::NodeSettings => {
                            if node_settings__.is_some() {
                                return Err(serde::de::Error::duplicate_field("nodeSettings"));
                            }
                            node_settings__ = map_.next_value()?;
                        }
                        GeneratedField::DotnetSettings => {
                            if dotnet_settings__.is_some() {
                                return Err(serde::de::Error::duplicate_field("dotnetSettings"));
                            }
                            dotnet_settings__ = map_.next_value()?;
                        }
                        GeneratedField::RubySettings => {
                            if ruby_settings__.is_some() {
                                return Err(serde::de::Error::duplicate_field("rubySettings"));
                            }
                            ruby_settings__ = map_.next_value()?;
                        }
                        GeneratedField::GoSettings => {
                            if go_settings__.is_some() {
                                return Err(serde::de::Error::duplicate_field("goSettings"));
                            }
                            go_settings__ = map_.next_value()?;
                        }
                    }
                }
                Ok(ClientLibrarySettings {
                    version: version__.unwrap_or_default(),
                    launch_stage: launch_stage__.unwrap_or_default(),
                    rest_numeric_enums: rest_numeric_enums__.unwrap_or_default(),
                    java_settings: java_settings__,
                    cpp_settings: cpp_settings__,
                    php_settings: php_settings__,
                    python_settings: python_settings__,
                    node_settings: node_settings__,
                    dotnet_settings: dotnet_settings__,
                    ruby_settings: ruby_settings__,
                    go_settings: go_settings__,
                })
            }
        }
        deserializer.deserialize_struct("google.api.ClientLibrarySettings", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for CommonLanguageSettings {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.reference_docs_uri.is_empty() {
            len += 1;
        }
        if !self.destinations.is_empty() {
            len += 1;
        }
        if self.selective_gapic_generation.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.CommonLanguageSettings", len)?;
        if !self.reference_docs_uri.is_empty() {
            struct_ser.serialize_field("referenceDocsUri", &self.reference_docs_uri)?;
        }
        if !self.destinations.is_empty() {
            let v = self.destinations.iter().cloned().map(|v| {
                ClientLibraryDestination::try_from(v)
                    .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", v)))
                }).collect::<std::result::Result<Vec<_>, _>>()?;
            struct_ser.serialize_field("destinations", &v)?;
        }
        if let Some(v) = self.selective_gapic_generation.as_ref() {
            struct_ser.serialize_field("selectiveGapicGeneration", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for CommonLanguageSettings {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "reference_docs_uri",
            "referenceDocsUri",
            "destinations",
            "selective_gapic_generation",
            "selectiveGapicGeneration",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            ReferenceDocsUri,
            Destinations,
            SelectiveGapicGeneration,
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
                            "referenceDocsUri" | "reference_docs_uri" => Ok(GeneratedField::ReferenceDocsUri),
                            "destinations" => Ok(GeneratedField::Destinations),
                            "selectiveGapicGeneration" | "selective_gapic_generation" => Ok(GeneratedField::SelectiveGapicGeneration),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = CommonLanguageSettings;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.CommonLanguageSettings")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<CommonLanguageSettings, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut reference_docs_uri__ = None;
                let mut destinations__ = None;
                let mut selective_gapic_generation__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::ReferenceDocsUri => {
                            if reference_docs_uri__.is_some() {
                                return Err(serde::de::Error::duplicate_field("referenceDocsUri"));
                            }
                            reference_docs_uri__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Destinations => {
                            if destinations__.is_some() {
                                return Err(serde::de::Error::duplicate_field("destinations"));
                            }
                            destinations__ = Some(map_.next_value::<Vec<ClientLibraryDestination>>()?.into_iter().map(|x| x as i32).collect());
                        }
                        GeneratedField::SelectiveGapicGeneration => {
                            if selective_gapic_generation__.is_some() {
                                return Err(serde::de::Error::duplicate_field("selectiveGapicGeneration"));
                            }
                            selective_gapic_generation__ = map_.next_value()?;
                        }
                    }
                }
                Ok(CommonLanguageSettings {
                    reference_docs_uri: reference_docs_uri__.unwrap_or_default(),
                    destinations: destinations__.unwrap_or_default(),
                    selective_gapic_generation: selective_gapic_generation__,
                })
            }
        }
        deserializer.deserialize_struct("google.api.CommonLanguageSettings", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for CppSettings {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.common.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.CppSettings", len)?;
        if let Some(v) = self.common.as_ref() {
            struct_ser.serialize_field("common", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for CppSettings {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "common",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Common,
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
                            "common" => Ok(GeneratedField::Common),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = CppSettings;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.CppSettings")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<CppSettings, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut common__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Common => {
                            if common__.is_some() {
                                return Err(serde::de::Error::duplicate_field("common"));
                            }
                            common__ = map_.next_value()?;
                        }
                    }
                }
                Ok(CppSettings {
                    common: common__,
                })
            }
        }
        deserializer.deserialize_struct("google.api.CppSettings", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for CustomHttpPattern {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.kind.is_empty() {
            len += 1;
        }
        if !self.path.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.CustomHttpPattern", len)?;
        if !self.kind.is_empty() {
            struct_ser.serialize_field("kind", &self.kind)?;
        }
        if !self.path.is_empty() {
            struct_ser.serialize_field("path", &self.path)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for CustomHttpPattern {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "kind",
            "path",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Kind,
            Path,
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
                            "kind" => Ok(GeneratedField::Kind),
                            "path" => Ok(GeneratedField::Path),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = CustomHttpPattern;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.CustomHttpPattern")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<CustomHttpPattern, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut kind__ = None;
                let mut path__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Kind => {
                            if kind__.is_some() {
                                return Err(serde::de::Error::duplicate_field("kind"));
                            }
                            kind__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Path => {
                            if path__.is_some() {
                                return Err(serde::de::Error::duplicate_field("path"));
                            }
                            path__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(CustomHttpPattern {
                    kind: kind__.unwrap_or_default(),
                    path: path__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("google.api.CustomHttpPattern", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for DotnetSettings {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.common.is_some() {
            len += 1;
        }
        if !self.renamed_services.is_empty() {
            len += 1;
        }
        if !self.renamed_resources.is_empty() {
            len += 1;
        }
        if !self.ignored_resources.is_empty() {
            len += 1;
        }
        if !self.forced_namespace_aliases.is_empty() {
            len += 1;
        }
        if !self.handwritten_signatures.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.DotnetSettings", len)?;
        if let Some(v) = self.common.as_ref() {
            struct_ser.serialize_field("common", v)?;
        }
        if !self.renamed_services.is_empty() {
            struct_ser.serialize_field("renamedServices", &self.renamed_services)?;
        }
        if !self.renamed_resources.is_empty() {
            struct_ser.serialize_field("renamedResources", &self.renamed_resources)?;
        }
        if !self.ignored_resources.is_empty() {
            struct_ser.serialize_field("ignoredResources", &self.ignored_resources)?;
        }
        if !self.forced_namespace_aliases.is_empty() {
            struct_ser.serialize_field("forcedNamespaceAliases", &self.forced_namespace_aliases)?;
        }
        if !self.handwritten_signatures.is_empty() {
            struct_ser.serialize_field("handwrittenSignatures", &self.handwritten_signatures)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for DotnetSettings {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "common",
            "renamed_services",
            "renamedServices",
            "renamed_resources",
            "renamedResources",
            "ignored_resources",
            "ignoredResources",
            "forced_namespace_aliases",
            "forcedNamespaceAliases",
            "handwritten_signatures",
            "handwrittenSignatures",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Common,
            RenamedServices,
            RenamedResources,
            IgnoredResources,
            ForcedNamespaceAliases,
            HandwrittenSignatures,
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
                            "common" => Ok(GeneratedField::Common),
                            "renamedServices" | "renamed_services" => Ok(GeneratedField::RenamedServices),
                            "renamedResources" | "renamed_resources" => Ok(GeneratedField::RenamedResources),
                            "ignoredResources" | "ignored_resources" => Ok(GeneratedField::IgnoredResources),
                            "forcedNamespaceAliases" | "forced_namespace_aliases" => Ok(GeneratedField::ForcedNamespaceAliases),
                            "handwrittenSignatures" | "handwritten_signatures" => Ok(GeneratedField::HandwrittenSignatures),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = DotnetSettings;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.DotnetSettings")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<DotnetSettings, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut common__ = None;
                let mut renamed_services__ = None;
                let mut renamed_resources__ = None;
                let mut ignored_resources__ = None;
                let mut forced_namespace_aliases__ = None;
                let mut handwritten_signatures__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Common => {
                            if common__.is_some() {
                                return Err(serde::de::Error::duplicate_field("common"));
                            }
                            common__ = map_.next_value()?;
                        }
                        GeneratedField::RenamedServices => {
                            if renamed_services__.is_some() {
                                return Err(serde::de::Error::duplicate_field("renamedServices"));
                            }
                            renamed_services__ = Some(
                                map_.next_value::<std::collections::HashMap<_, _>>()?
                            );
                        }
                        GeneratedField::RenamedResources => {
                            if renamed_resources__.is_some() {
                                return Err(serde::de::Error::duplicate_field("renamedResources"));
                            }
                            renamed_resources__ = Some(
                                map_.next_value::<std::collections::HashMap<_, _>>()?
                            );
                        }
                        GeneratedField::IgnoredResources => {
                            if ignored_resources__.is_some() {
                                return Err(serde::de::Error::duplicate_field("ignoredResources"));
                            }
                            ignored_resources__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ForcedNamespaceAliases => {
                            if forced_namespace_aliases__.is_some() {
                                return Err(serde::de::Error::duplicate_field("forcedNamespaceAliases"));
                            }
                            forced_namespace_aliases__ = Some(map_.next_value()?);
                        }
                        GeneratedField::HandwrittenSignatures => {
                            if handwritten_signatures__.is_some() {
                                return Err(serde::de::Error::duplicate_field("handwrittenSignatures"));
                            }
                            handwritten_signatures__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(DotnetSettings {
                    common: common__,
                    renamed_services: renamed_services__.unwrap_or_default(),
                    renamed_resources: renamed_resources__.unwrap_or_default(),
                    ignored_resources: ignored_resources__.unwrap_or_default(),
                    forced_namespace_aliases: forced_namespace_aliases__.unwrap_or_default(),
                    handwritten_signatures: handwritten_signatures__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("google.api.DotnetSettings", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for FieldBehavior {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let variant = match self {
            Self::Unspecified => "FIELD_BEHAVIOR_UNSPECIFIED",
            Self::Optional => "OPTIONAL",
            Self::Required => "REQUIRED",
            Self::OutputOnly => "OUTPUT_ONLY",
            Self::InputOnly => "INPUT_ONLY",
            Self::Immutable => "IMMUTABLE",
            Self::UnorderedList => "UNORDERED_LIST",
            Self::NonEmptyDefault => "NON_EMPTY_DEFAULT",
            Self::Identifier => "IDENTIFIER",
        };
        serializer.serialize_str(variant)
    }
}
impl<'de> serde::Deserialize<'de> for FieldBehavior {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "FIELD_BEHAVIOR_UNSPECIFIED",
            "OPTIONAL",
            "REQUIRED",
            "OUTPUT_ONLY",
            "INPUT_ONLY",
            "IMMUTABLE",
            "UNORDERED_LIST",
            "NON_EMPTY_DEFAULT",
            "IDENTIFIER",
        ];

        struct GeneratedVisitor;

        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = FieldBehavior;

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
                    "FIELD_BEHAVIOR_UNSPECIFIED" => Ok(FieldBehavior::Unspecified),
                    "OPTIONAL" => Ok(FieldBehavior::Optional),
                    "REQUIRED" => Ok(FieldBehavior::Required),
                    "OUTPUT_ONLY" => Ok(FieldBehavior::OutputOnly),
                    "INPUT_ONLY" => Ok(FieldBehavior::InputOnly),
                    "IMMUTABLE" => Ok(FieldBehavior::Immutable),
                    "UNORDERED_LIST" => Ok(FieldBehavior::UnorderedList),
                    "NON_EMPTY_DEFAULT" => Ok(FieldBehavior::NonEmptyDefault),
                    "IDENTIFIER" => Ok(FieldBehavior::Identifier),
                    _ => Err(serde::de::Error::unknown_variant(value, FIELDS)),
                }
            }
        }
        deserializer.deserialize_any(GeneratedVisitor)
    }
}
impl serde::Serialize for FlowControlLimitExceededBehaviorProto {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let variant = match self {
            Self::UnsetBehavior => "UNSET_BEHAVIOR",
            Self::ThrowException => "THROW_EXCEPTION",
            Self::Block => "BLOCK",
            Self::Ignore => "IGNORE",
        };
        serializer.serialize_str(variant)
    }
}
impl<'de> serde::Deserialize<'de> for FlowControlLimitExceededBehaviorProto {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "UNSET_BEHAVIOR",
            "THROW_EXCEPTION",
            "BLOCK",
            "IGNORE",
        ];

        struct GeneratedVisitor;

        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = FlowControlLimitExceededBehaviorProto;

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
                    "UNSET_BEHAVIOR" => Ok(FlowControlLimitExceededBehaviorProto::UnsetBehavior),
                    "THROW_EXCEPTION" => Ok(FlowControlLimitExceededBehaviorProto::ThrowException),
                    "BLOCK" => Ok(FlowControlLimitExceededBehaviorProto::Block),
                    "IGNORE" => Ok(FlowControlLimitExceededBehaviorProto::Ignore),
                    _ => Err(serde::de::Error::unknown_variant(value, FIELDS)),
                }
            }
        }
        deserializer.deserialize_any(GeneratedVisitor)
    }
}
impl serde::Serialize for GoSettings {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.common.is_some() {
            len += 1;
        }
        if !self.renamed_services.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.GoSettings", len)?;
        if let Some(v) = self.common.as_ref() {
            struct_ser.serialize_field("common", v)?;
        }
        if !self.renamed_services.is_empty() {
            struct_ser.serialize_field("renamedServices", &self.renamed_services)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for GoSettings {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "common",
            "renamed_services",
            "renamedServices",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Common,
            RenamedServices,
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
                            "common" => Ok(GeneratedField::Common),
                            "renamedServices" | "renamed_services" => Ok(GeneratedField::RenamedServices),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = GoSettings;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.GoSettings")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<GoSettings, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut common__ = None;
                let mut renamed_services__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Common => {
                            if common__.is_some() {
                                return Err(serde::de::Error::duplicate_field("common"));
                            }
                            common__ = map_.next_value()?;
                        }
                        GeneratedField::RenamedServices => {
                            if renamed_services__.is_some() {
                                return Err(serde::de::Error::duplicate_field("renamedServices"));
                            }
                            renamed_services__ = Some(
                                map_.next_value::<std::collections::HashMap<_, _>>()?
                            );
                        }
                    }
                }
                Ok(GoSettings {
                    common: common__,
                    renamed_services: renamed_services__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("google.api.GoSettings", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for Http {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.rules.is_empty() {
            len += 1;
        }
        if self.fully_decode_reserved_expansion {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.Http", len)?;
        if !self.rules.is_empty() {
            struct_ser.serialize_field("rules", &self.rules)?;
        }
        if self.fully_decode_reserved_expansion {
            struct_ser.serialize_field("fullyDecodeReservedExpansion", &self.fully_decode_reserved_expansion)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for Http {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "rules",
            "fully_decode_reserved_expansion",
            "fullyDecodeReservedExpansion",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Rules,
            FullyDecodeReservedExpansion,
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
                            "rules" => Ok(GeneratedField::Rules),
                            "fullyDecodeReservedExpansion" | "fully_decode_reserved_expansion" => Ok(GeneratedField::FullyDecodeReservedExpansion),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = Http;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.Http")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<Http, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut rules__ = None;
                let mut fully_decode_reserved_expansion__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Rules => {
                            if rules__.is_some() {
                                return Err(serde::de::Error::duplicate_field("rules"));
                            }
                            rules__ = Some(map_.next_value()?);
                        }
                        GeneratedField::FullyDecodeReservedExpansion => {
                            if fully_decode_reserved_expansion__.is_some() {
                                return Err(serde::de::Error::duplicate_field("fullyDecodeReservedExpansion"));
                            }
                            fully_decode_reserved_expansion__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(Http {
                    rules: rules__.unwrap_or_default(),
                    fully_decode_reserved_expansion: fully_decode_reserved_expansion__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("google.api.Http", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for HttpRule {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.selector.is_empty() {
            len += 1;
        }
        if !self.body.is_empty() {
            len += 1;
        }
        if !self.response_body.is_empty() {
            len += 1;
        }
        if !self.additional_bindings.is_empty() {
            len += 1;
        }
        if self.pattern.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.HttpRule", len)?;
        if !self.selector.is_empty() {
            struct_ser.serialize_field("selector", &self.selector)?;
        }
        if !self.body.is_empty() {
            struct_ser.serialize_field("body", &self.body)?;
        }
        if !self.response_body.is_empty() {
            struct_ser.serialize_field("responseBody", &self.response_body)?;
        }
        if !self.additional_bindings.is_empty() {
            struct_ser.serialize_field("additionalBindings", &self.additional_bindings)?;
        }
        if let Some(v) = self.pattern.as_ref() {
            match v {
                http_rule::Pattern::Get(v) => {
                    struct_ser.serialize_field("get", v)?;
                }
                http_rule::Pattern::Put(v) => {
                    struct_ser.serialize_field("put", v)?;
                }
                http_rule::Pattern::Post(v) => {
                    struct_ser.serialize_field("post", v)?;
                }
                http_rule::Pattern::Delete(v) => {
                    struct_ser.serialize_field("delete", v)?;
                }
                http_rule::Pattern::Patch(v) => {
                    struct_ser.serialize_field("patch", v)?;
                }
                http_rule::Pattern::Custom(v) => {
                    struct_ser.serialize_field("custom", v)?;
                }
            }
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for HttpRule {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "selector",
            "body",
            "response_body",
            "responseBody",
            "additional_bindings",
            "additionalBindings",
            "get",
            "put",
            "post",
            "delete",
            "patch",
            "custom",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Selector,
            Body,
            ResponseBody,
            AdditionalBindings,
            Get,
            Put,
            Post,
            Delete,
            Patch,
            Custom,
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
                            "selector" => Ok(GeneratedField::Selector),
                            "body" => Ok(GeneratedField::Body),
                            "responseBody" | "response_body" => Ok(GeneratedField::ResponseBody),
                            "additionalBindings" | "additional_bindings" => Ok(GeneratedField::AdditionalBindings),
                            "get" => Ok(GeneratedField::Get),
                            "put" => Ok(GeneratedField::Put),
                            "post" => Ok(GeneratedField::Post),
                            "delete" => Ok(GeneratedField::Delete),
                            "patch" => Ok(GeneratedField::Patch),
                            "custom" => Ok(GeneratedField::Custom),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = HttpRule;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.HttpRule")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<HttpRule, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut selector__ = None;
                let mut body__ = None;
                let mut response_body__ = None;
                let mut additional_bindings__ = None;
                let mut pattern__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Selector => {
                            if selector__.is_some() {
                                return Err(serde::de::Error::duplicate_field("selector"));
                            }
                            selector__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Body => {
                            if body__.is_some() {
                                return Err(serde::de::Error::duplicate_field("body"));
                            }
                            body__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ResponseBody => {
                            if response_body__.is_some() {
                                return Err(serde::de::Error::duplicate_field("responseBody"));
                            }
                            response_body__ = Some(map_.next_value()?);
                        }
                        GeneratedField::AdditionalBindings => {
                            if additional_bindings__.is_some() {
                                return Err(serde::de::Error::duplicate_field("additionalBindings"));
                            }
                            additional_bindings__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Get => {
                            if pattern__.is_some() {
                                return Err(serde::de::Error::duplicate_field("get"));
                            }
                            pattern__ = map_.next_value::<::std::option::Option<_>>()?.map(http_rule::Pattern::Get);
                        }
                        GeneratedField::Put => {
                            if pattern__.is_some() {
                                return Err(serde::de::Error::duplicate_field("put"));
                            }
                            pattern__ = map_.next_value::<::std::option::Option<_>>()?.map(http_rule::Pattern::Put);
                        }
                        GeneratedField::Post => {
                            if pattern__.is_some() {
                                return Err(serde::de::Error::duplicate_field("post"));
                            }
                            pattern__ = map_.next_value::<::std::option::Option<_>>()?.map(http_rule::Pattern::Post);
                        }
                        GeneratedField::Delete => {
                            if pattern__.is_some() {
                                return Err(serde::de::Error::duplicate_field("delete"));
                            }
                            pattern__ = map_.next_value::<::std::option::Option<_>>()?.map(http_rule::Pattern::Delete);
                        }
                        GeneratedField::Patch => {
                            if pattern__.is_some() {
                                return Err(serde::de::Error::duplicate_field("patch"));
                            }
                            pattern__ = map_.next_value::<::std::option::Option<_>>()?.map(http_rule::Pattern::Patch);
                        }
                        GeneratedField::Custom => {
                            if pattern__.is_some() {
                                return Err(serde::de::Error::duplicate_field("custom"));
                            }
                            pattern__ = map_.next_value::<::std::option::Option<_>>()?.map(http_rule::Pattern::Custom)
;
                        }
                    }
                }
                Ok(HttpRule {
                    selector: selector__.unwrap_or_default(),
                    body: body__.unwrap_or_default(),
                    response_body: response_body__.unwrap_or_default(),
                    additional_bindings: additional_bindings__.unwrap_or_default(),
                    pattern: pattern__,
                })
            }
        }
        deserializer.deserialize_struct("google.api.HttpRule", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for JavaSettings {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.library_package.is_empty() {
            len += 1;
        }
        if !self.service_class_names.is_empty() {
            len += 1;
        }
        if self.common.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.JavaSettings", len)?;
        if !self.library_package.is_empty() {
            struct_ser.serialize_field("libraryPackage", &self.library_package)?;
        }
        if !self.service_class_names.is_empty() {
            struct_ser.serialize_field("serviceClassNames", &self.service_class_names)?;
        }
        if let Some(v) = self.common.as_ref() {
            struct_ser.serialize_field("common", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for JavaSettings {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "library_package",
            "libraryPackage",
            "service_class_names",
            "serviceClassNames",
            "common",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            LibraryPackage,
            ServiceClassNames,
            Common,
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
                            "libraryPackage" | "library_package" => Ok(GeneratedField::LibraryPackage),
                            "serviceClassNames" | "service_class_names" => Ok(GeneratedField::ServiceClassNames),
                            "common" => Ok(GeneratedField::Common),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = JavaSettings;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.JavaSettings")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<JavaSettings, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut library_package__ = None;
                let mut service_class_names__ = None;
                let mut common__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::LibraryPackage => {
                            if library_package__.is_some() {
                                return Err(serde::de::Error::duplicate_field("libraryPackage"));
                            }
                            library_package__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ServiceClassNames => {
                            if service_class_names__.is_some() {
                                return Err(serde::de::Error::duplicate_field("serviceClassNames"));
                            }
                            service_class_names__ = Some(
                                map_.next_value::<std::collections::HashMap<_, _>>()?
                            );
                        }
                        GeneratedField::Common => {
                            if common__.is_some() {
                                return Err(serde::de::Error::duplicate_field("common"));
                            }
                            common__ = map_.next_value()?;
                        }
                    }
                }
                Ok(JavaSettings {
                    library_package: library_package__.unwrap_or_default(),
                    service_class_names: service_class_names__.unwrap_or_default(),
                    common: common__,
                })
            }
        }
        deserializer.deserialize_struct("google.api.JavaSettings", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for LaunchStage {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let variant = match self {
            Self::Unspecified => "LAUNCH_STAGE_UNSPECIFIED",
            Self::Unimplemented => "UNIMPLEMENTED",
            Self::Prelaunch => "PRELAUNCH",
            Self::EarlyAccess => "EARLY_ACCESS",
            Self::Alpha => "ALPHA",
            Self::Beta => "BETA",
            Self::Ga => "GA",
            Self::Deprecated => "DEPRECATED",
        };
        serializer.serialize_str(variant)
    }
}
impl<'de> serde::Deserialize<'de> for LaunchStage {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "LAUNCH_STAGE_UNSPECIFIED",
            "UNIMPLEMENTED",
            "PRELAUNCH",
            "EARLY_ACCESS",
            "ALPHA",
            "BETA",
            "GA",
            "DEPRECATED",
        ];

        struct GeneratedVisitor;

        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = LaunchStage;

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
                    "LAUNCH_STAGE_UNSPECIFIED" => Ok(LaunchStage::Unspecified),
                    "UNIMPLEMENTED" => Ok(LaunchStage::Unimplemented),
                    "PRELAUNCH" => Ok(LaunchStage::Prelaunch),
                    "EARLY_ACCESS" => Ok(LaunchStage::EarlyAccess),
                    "ALPHA" => Ok(LaunchStage::Alpha),
                    "BETA" => Ok(LaunchStage::Beta),
                    "GA" => Ok(LaunchStage::Ga),
                    "DEPRECATED" => Ok(LaunchStage::Deprecated),
                    _ => Err(serde::de::Error::unknown_variant(value, FIELDS)),
                }
            }
        }
        deserializer.deserialize_any(GeneratedVisitor)
    }
}
impl serde::Serialize for MethodSettings {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.selector.is_empty() {
            len += 1;
        }
        if self.long_running.is_some() {
            len += 1;
        }
        if !self.auto_populated_fields.is_empty() {
            len += 1;
        }
        if self.batching.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.MethodSettings", len)?;
        if !self.selector.is_empty() {
            struct_ser.serialize_field("selector", &self.selector)?;
        }
        if let Some(v) = self.long_running.as_ref() {
            struct_ser.serialize_field("longRunning", v)?;
        }
        if !self.auto_populated_fields.is_empty() {
            struct_ser.serialize_field("autoPopulatedFields", &self.auto_populated_fields)?;
        }
        if let Some(v) = self.batching.as_ref() {
            struct_ser.serialize_field("batching", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for MethodSettings {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "selector",
            "long_running",
            "longRunning",
            "auto_populated_fields",
            "autoPopulatedFields",
            "batching",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Selector,
            LongRunning,
            AutoPopulatedFields,
            Batching,
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
                            "selector" => Ok(GeneratedField::Selector),
                            "longRunning" | "long_running" => Ok(GeneratedField::LongRunning),
                            "autoPopulatedFields" | "auto_populated_fields" => Ok(GeneratedField::AutoPopulatedFields),
                            "batching" => Ok(GeneratedField::Batching),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = MethodSettings;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.MethodSettings")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<MethodSettings, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut selector__ = None;
                let mut long_running__ = None;
                let mut auto_populated_fields__ = None;
                let mut batching__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Selector => {
                            if selector__.is_some() {
                                return Err(serde::de::Error::duplicate_field("selector"));
                            }
                            selector__ = Some(map_.next_value()?);
                        }
                        GeneratedField::LongRunning => {
                            if long_running__.is_some() {
                                return Err(serde::de::Error::duplicate_field("longRunning"));
                            }
                            long_running__ = map_.next_value()?;
                        }
                        GeneratedField::AutoPopulatedFields => {
                            if auto_populated_fields__.is_some() {
                                return Err(serde::de::Error::duplicate_field("autoPopulatedFields"));
                            }
                            auto_populated_fields__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Batching => {
                            if batching__.is_some() {
                                return Err(serde::de::Error::duplicate_field("batching"));
                            }
                            batching__ = map_.next_value()?;
                        }
                    }
                }
                Ok(MethodSettings {
                    selector: selector__.unwrap_or_default(),
                    long_running: long_running__,
                    auto_populated_fields: auto_populated_fields__.unwrap_or_default(),
                    batching: batching__,
                })
            }
        }
        deserializer.deserialize_struct("google.api.MethodSettings", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for method_settings::LongRunning {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.initial_poll_delay.is_some() {
            len += 1;
        }
        if self.poll_delay_multiplier != 0. {
            len += 1;
        }
        if self.max_poll_delay.is_some() {
            len += 1;
        }
        if self.total_poll_timeout.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.MethodSettings.LongRunning", len)?;
        if let Some(v) = self.initial_poll_delay.as_ref() {
            struct_ser.serialize_field("initialPollDelay", v)?;
        }
        if self.poll_delay_multiplier != 0. {
            struct_ser.serialize_field("pollDelayMultiplier", &self.poll_delay_multiplier)?;
        }
        if let Some(v) = self.max_poll_delay.as_ref() {
            struct_ser.serialize_field("maxPollDelay", v)?;
        }
        if let Some(v) = self.total_poll_timeout.as_ref() {
            struct_ser.serialize_field("totalPollTimeout", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for method_settings::LongRunning {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "initial_poll_delay",
            "initialPollDelay",
            "poll_delay_multiplier",
            "pollDelayMultiplier",
            "max_poll_delay",
            "maxPollDelay",
            "total_poll_timeout",
            "totalPollTimeout",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            InitialPollDelay,
            PollDelayMultiplier,
            MaxPollDelay,
            TotalPollTimeout,
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
                            "initialPollDelay" | "initial_poll_delay" => Ok(GeneratedField::InitialPollDelay),
                            "pollDelayMultiplier" | "poll_delay_multiplier" => Ok(GeneratedField::PollDelayMultiplier),
                            "maxPollDelay" | "max_poll_delay" => Ok(GeneratedField::MaxPollDelay),
                            "totalPollTimeout" | "total_poll_timeout" => Ok(GeneratedField::TotalPollTimeout),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = method_settings::LongRunning;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.MethodSettings.LongRunning")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<method_settings::LongRunning, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut initial_poll_delay__ = None;
                let mut poll_delay_multiplier__ = None;
                let mut max_poll_delay__ = None;
                let mut total_poll_timeout__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::InitialPollDelay => {
                            if initial_poll_delay__.is_some() {
                                return Err(serde::de::Error::duplicate_field("initialPollDelay"));
                            }
                            initial_poll_delay__ = map_.next_value()?;
                        }
                        GeneratedField::PollDelayMultiplier => {
                            if poll_delay_multiplier__.is_some() {
                                return Err(serde::de::Error::duplicate_field("pollDelayMultiplier"));
                            }
                            poll_delay_multiplier__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::MaxPollDelay => {
                            if max_poll_delay__.is_some() {
                                return Err(serde::de::Error::duplicate_field("maxPollDelay"));
                            }
                            max_poll_delay__ = map_.next_value()?;
                        }
                        GeneratedField::TotalPollTimeout => {
                            if total_poll_timeout__.is_some() {
                                return Err(serde::de::Error::duplicate_field("totalPollTimeout"));
                            }
                            total_poll_timeout__ = map_.next_value()?;
                        }
                    }
                }
                Ok(method_settings::LongRunning {
                    initial_poll_delay: initial_poll_delay__,
                    poll_delay_multiplier: poll_delay_multiplier__.unwrap_or_default(),
                    max_poll_delay: max_poll_delay__,
                    total_poll_timeout: total_poll_timeout__,
                })
            }
        }
        deserializer.deserialize_struct("google.api.MethodSettings.LongRunning", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for NodeSettings {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.common.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.NodeSettings", len)?;
        if let Some(v) = self.common.as_ref() {
            struct_ser.serialize_field("common", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for NodeSettings {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "common",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Common,
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
                            "common" => Ok(GeneratedField::Common),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = NodeSettings;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.NodeSettings")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<NodeSettings, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut common__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Common => {
                            if common__.is_some() {
                                return Err(serde::de::Error::duplicate_field("common"));
                            }
                            common__ = map_.next_value()?;
                        }
                    }
                }
                Ok(NodeSettings {
                    common: common__,
                })
            }
        }
        deserializer.deserialize_struct("google.api.NodeSettings", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for PhpSettings {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.common.is_some() {
            len += 1;
        }
        if !self.library_package.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.PhpSettings", len)?;
        if let Some(v) = self.common.as_ref() {
            struct_ser.serialize_field("common", v)?;
        }
        if !self.library_package.is_empty() {
            struct_ser.serialize_field("libraryPackage", &self.library_package)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for PhpSettings {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "common",
            "library_package",
            "libraryPackage",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Common,
            LibraryPackage,
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
                            "common" => Ok(GeneratedField::Common),
                            "libraryPackage" | "library_package" => Ok(GeneratedField::LibraryPackage),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = PhpSettings;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.PhpSettings")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<PhpSettings, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut common__ = None;
                let mut library_package__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Common => {
                            if common__.is_some() {
                                return Err(serde::de::Error::duplicate_field("common"));
                            }
                            common__ = map_.next_value()?;
                        }
                        GeneratedField::LibraryPackage => {
                            if library_package__.is_some() {
                                return Err(serde::de::Error::duplicate_field("libraryPackage"));
                            }
                            library_package__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(PhpSettings {
                    common: common__,
                    library_package: library_package__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("google.api.PhpSettings", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for Publishing {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.method_settings.is_empty() {
            len += 1;
        }
        if !self.new_issue_uri.is_empty() {
            len += 1;
        }
        if !self.documentation_uri.is_empty() {
            len += 1;
        }
        if !self.api_short_name.is_empty() {
            len += 1;
        }
        if !self.github_label.is_empty() {
            len += 1;
        }
        if !self.codeowner_github_teams.is_empty() {
            len += 1;
        }
        if !self.doc_tag_prefix.is_empty() {
            len += 1;
        }
        if self.organization != 0 {
            len += 1;
        }
        if !self.library_settings.is_empty() {
            len += 1;
        }
        if !self.proto_reference_documentation_uri.is_empty() {
            len += 1;
        }
        if !self.rest_reference_documentation_uri.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.Publishing", len)?;
        if !self.method_settings.is_empty() {
            struct_ser.serialize_field("methodSettings", &self.method_settings)?;
        }
        if !self.new_issue_uri.is_empty() {
            struct_ser.serialize_field("newIssueUri", &self.new_issue_uri)?;
        }
        if !self.documentation_uri.is_empty() {
            struct_ser.serialize_field("documentationUri", &self.documentation_uri)?;
        }
        if !self.api_short_name.is_empty() {
            struct_ser.serialize_field("apiShortName", &self.api_short_name)?;
        }
        if !self.github_label.is_empty() {
            struct_ser.serialize_field("githubLabel", &self.github_label)?;
        }
        if !self.codeowner_github_teams.is_empty() {
            struct_ser.serialize_field("codeownerGithubTeams", &self.codeowner_github_teams)?;
        }
        if !self.doc_tag_prefix.is_empty() {
            struct_ser.serialize_field("docTagPrefix", &self.doc_tag_prefix)?;
        }
        if self.organization != 0 {
            let v = ClientLibraryOrganization::try_from(self.organization)
                .map_err(|_| serde::ser::Error::custom(format!("Invalid variant {}", self.organization)))?;
            struct_ser.serialize_field("organization", &v)?;
        }
        if !self.library_settings.is_empty() {
            struct_ser.serialize_field("librarySettings", &self.library_settings)?;
        }
        if !self.proto_reference_documentation_uri.is_empty() {
            struct_ser.serialize_field("protoReferenceDocumentationUri", &self.proto_reference_documentation_uri)?;
        }
        if !self.rest_reference_documentation_uri.is_empty() {
            struct_ser.serialize_field("restReferenceDocumentationUri", &self.rest_reference_documentation_uri)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for Publishing {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "method_settings",
            "methodSettings",
            "new_issue_uri",
            "newIssueUri",
            "documentation_uri",
            "documentationUri",
            "api_short_name",
            "apiShortName",
            "github_label",
            "githubLabel",
            "codeowner_github_teams",
            "codeownerGithubTeams",
            "doc_tag_prefix",
            "docTagPrefix",
            "organization",
            "library_settings",
            "librarySettings",
            "proto_reference_documentation_uri",
            "protoReferenceDocumentationUri",
            "rest_reference_documentation_uri",
            "restReferenceDocumentationUri",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            MethodSettings,
            NewIssueUri,
            DocumentationUri,
            ApiShortName,
            GithubLabel,
            CodeownerGithubTeams,
            DocTagPrefix,
            Organization,
            LibrarySettings,
            ProtoReferenceDocumentationUri,
            RestReferenceDocumentationUri,
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
                            "methodSettings" | "method_settings" => Ok(GeneratedField::MethodSettings),
                            "newIssueUri" | "new_issue_uri" => Ok(GeneratedField::NewIssueUri),
                            "documentationUri" | "documentation_uri" => Ok(GeneratedField::DocumentationUri),
                            "apiShortName" | "api_short_name" => Ok(GeneratedField::ApiShortName),
                            "githubLabel" | "github_label" => Ok(GeneratedField::GithubLabel),
                            "codeownerGithubTeams" | "codeowner_github_teams" => Ok(GeneratedField::CodeownerGithubTeams),
                            "docTagPrefix" | "doc_tag_prefix" => Ok(GeneratedField::DocTagPrefix),
                            "organization" => Ok(GeneratedField::Organization),
                            "librarySettings" | "library_settings" => Ok(GeneratedField::LibrarySettings),
                            "protoReferenceDocumentationUri" | "proto_reference_documentation_uri" => Ok(GeneratedField::ProtoReferenceDocumentationUri),
                            "restReferenceDocumentationUri" | "rest_reference_documentation_uri" => Ok(GeneratedField::RestReferenceDocumentationUri),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = Publishing;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.Publishing")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<Publishing, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut method_settings__ = None;
                let mut new_issue_uri__ = None;
                let mut documentation_uri__ = None;
                let mut api_short_name__ = None;
                let mut github_label__ = None;
                let mut codeowner_github_teams__ = None;
                let mut doc_tag_prefix__ = None;
                let mut organization__ = None;
                let mut library_settings__ = None;
                let mut proto_reference_documentation_uri__ = None;
                let mut rest_reference_documentation_uri__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::MethodSettings => {
                            if method_settings__.is_some() {
                                return Err(serde::de::Error::duplicate_field("methodSettings"));
                            }
                            method_settings__ = Some(map_.next_value()?);
                        }
                        GeneratedField::NewIssueUri => {
                            if new_issue_uri__.is_some() {
                                return Err(serde::de::Error::duplicate_field("newIssueUri"));
                            }
                            new_issue_uri__ = Some(map_.next_value()?);
                        }
                        GeneratedField::DocumentationUri => {
                            if documentation_uri__.is_some() {
                                return Err(serde::de::Error::duplicate_field("documentationUri"));
                            }
                            documentation_uri__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ApiShortName => {
                            if api_short_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("apiShortName"));
                            }
                            api_short_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::GithubLabel => {
                            if github_label__.is_some() {
                                return Err(serde::de::Error::duplicate_field("githubLabel"));
                            }
                            github_label__ = Some(map_.next_value()?);
                        }
                        GeneratedField::CodeownerGithubTeams => {
                            if codeowner_github_teams__.is_some() {
                                return Err(serde::de::Error::duplicate_field("codeownerGithubTeams"));
                            }
                            codeowner_github_teams__ = Some(map_.next_value()?);
                        }
                        GeneratedField::DocTagPrefix => {
                            if doc_tag_prefix__.is_some() {
                                return Err(serde::de::Error::duplicate_field("docTagPrefix"));
                            }
                            doc_tag_prefix__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Organization => {
                            if organization__.is_some() {
                                return Err(serde::de::Error::duplicate_field("organization"));
                            }
                            organization__ = Some(map_.next_value::<ClientLibraryOrganization>()? as i32);
                        }
                        GeneratedField::LibrarySettings => {
                            if library_settings__.is_some() {
                                return Err(serde::de::Error::duplicate_field("librarySettings"));
                            }
                            library_settings__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ProtoReferenceDocumentationUri => {
                            if proto_reference_documentation_uri__.is_some() {
                                return Err(serde::de::Error::duplicate_field("protoReferenceDocumentationUri"));
                            }
                            proto_reference_documentation_uri__ = Some(map_.next_value()?);
                        }
                        GeneratedField::RestReferenceDocumentationUri => {
                            if rest_reference_documentation_uri__.is_some() {
                                return Err(serde::de::Error::duplicate_field("restReferenceDocumentationUri"));
                            }
                            rest_reference_documentation_uri__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(Publishing {
                    method_settings: method_settings__.unwrap_or_default(),
                    new_issue_uri: new_issue_uri__.unwrap_or_default(),
                    documentation_uri: documentation_uri__.unwrap_or_default(),
                    api_short_name: api_short_name__.unwrap_or_default(),
                    github_label: github_label__.unwrap_or_default(),
                    codeowner_github_teams: codeowner_github_teams__.unwrap_or_default(),
                    doc_tag_prefix: doc_tag_prefix__.unwrap_or_default(),
                    organization: organization__.unwrap_or_default(),
                    library_settings: library_settings__.unwrap_or_default(),
                    proto_reference_documentation_uri: proto_reference_documentation_uri__.unwrap_or_default(),
                    rest_reference_documentation_uri: rest_reference_documentation_uri__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("google.api.Publishing", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for PythonSettings {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.common.is_some() {
            len += 1;
        }
        if self.experimental_features.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.PythonSettings", len)?;
        if let Some(v) = self.common.as_ref() {
            struct_ser.serialize_field("common", v)?;
        }
        if let Some(v) = self.experimental_features.as_ref() {
            struct_ser.serialize_field("experimentalFeatures", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for PythonSettings {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "common",
            "experimental_features",
            "experimentalFeatures",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Common,
            ExperimentalFeatures,
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
                            "common" => Ok(GeneratedField::Common),
                            "experimentalFeatures" | "experimental_features" => Ok(GeneratedField::ExperimentalFeatures),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = PythonSettings;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.PythonSettings")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<PythonSettings, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut common__ = None;
                let mut experimental_features__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Common => {
                            if common__.is_some() {
                                return Err(serde::de::Error::duplicate_field("common"));
                            }
                            common__ = map_.next_value()?;
                        }
                        GeneratedField::ExperimentalFeatures => {
                            if experimental_features__.is_some() {
                                return Err(serde::de::Error::duplicate_field("experimentalFeatures"));
                            }
                            experimental_features__ = map_.next_value()?;
                        }
                    }
                }
                Ok(PythonSettings {
                    common: common__,
                    experimental_features: experimental_features__,
                })
            }
        }
        deserializer.deserialize_struct("google.api.PythonSettings", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for python_settings::ExperimentalFeatures {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.rest_async_io_enabled {
            len += 1;
        }
        if self.protobuf_pythonic_types_enabled {
            len += 1;
        }
        if self.unversioned_package_disabled {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.PythonSettings.ExperimentalFeatures", len)?;
        if self.rest_async_io_enabled {
            struct_ser.serialize_field("restAsyncIoEnabled", &self.rest_async_io_enabled)?;
        }
        if self.protobuf_pythonic_types_enabled {
            struct_ser.serialize_field("protobufPythonicTypesEnabled", &self.protobuf_pythonic_types_enabled)?;
        }
        if self.unversioned_package_disabled {
            struct_ser.serialize_field("unversionedPackageDisabled", &self.unversioned_package_disabled)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for python_settings::ExperimentalFeatures {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "rest_async_io_enabled",
            "restAsyncIoEnabled",
            "protobuf_pythonic_types_enabled",
            "protobufPythonicTypesEnabled",
            "unversioned_package_disabled",
            "unversionedPackageDisabled",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            RestAsyncIoEnabled,
            ProtobufPythonicTypesEnabled,
            UnversionedPackageDisabled,
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
                            "restAsyncIoEnabled" | "rest_async_io_enabled" => Ok(GeneratedField::RestAsyncIoEnabled),
                            "protobufPythonicTypesEnabled" | "protobuf_pythonic_types_enabled" => Ok(GeneratedField::ProtobufPythonicTypesEnabled),
                            "unversionedPackageDisabled" | "unversioned_package_disabled" => Ok(GeneratedField::UnversionedPackageDisabled),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = python_settings::ExperimentalFeatures;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.PythonSettings.ExperimentalFeatures")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<python_settings::ExperimentalFeatures, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut rest_async_io_enabled__ = None;
                let mut protobuf_pythonic_types_enabled__ = None;
                let mut unversioned_package_disabled__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::RestAsyncIoEnabled => {
                            if rest_async_io_enabled__.is_some() {
                                return Err(serde::de::Error::duplicate_field("restAsyncIoEnabled"));
                            }
                            rest_async_io_enabled__ = Some(map_.next_value()?);
                        }
                        GeneratedField::ProtobufPythonicTypesEnabled => {
                            if protobuf_pythonic_types_enabled__.is_some() {
                                return Err(serde::de::Error::duplicate_field("protobufPythonicTypesEnabled"));
                            }
                            protobuf_pythonic_types_enabled__ = Some(map_.next_value()?);
                        }
                        GeneratedField::UnversionedPackageDisabled => {
                            if unversioned_package_disabled__.is_some() {
                                return Err(serde::de::Error::duplicate_field("unversionedPackageDisabled"));
                            }
                            unversioned_package_disabled__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(python_settings::ExperimentalFeatures {
                    rest_async_io_enabled: rest_async_io_enabled__.unwrap_or_default(),
                    protobuf_pythonic_types_enabled: protobuf_pythonic_types_enabled__.unwrap_or_default(),
                    unversioned_package_disabled: unversioned_package_disabled__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("google.api.PythonSettings.ExperimentalFeatures", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for RubySettings {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.common.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.RubySettings", len)?;
        if let Some(v) = self.common.as_ref() {
            struct_ser.serialize_field("common", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for RubySettings {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "common",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Common,
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
                            "common" => Ok(GeneratedField::Common),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = RubySettings;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.RubySettings")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<RubySettings, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut common__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Common => {
                            if common__.is_some() {
                                return Err(serde::de::Error::duplicate_field("common"));
                            }
                            common__ = map_.next_value()?;
                        }
                    }
                }
                Ok(RubySettings {
                    common: common__,
                })
            }
        }
        deserializer.deserialize_struct("google.api.RubySettings", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for SelectiveGapicGeneration {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.methods.is_empty() {
            len += 1;
        }
        if self.generate_omitted_as_internal {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("google.api.SelectiveGapicGeneration", len)?;
        if !self.methods.is_empty() {
            struct_ser.serialize_field("methods", &self.methods)?;
        }
        if self.generate_omitted_as_internal {
            struct_ser.serialize_field("generateOmittedAsInternal", &self.generate_omitted_as_internal)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for SelectiveGapicGeneration {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "methods",
            "generate_omitted_as_internal",
            "generateOmittedAsInternal",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Methods,
            GenerateOmittedAsInternal,
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
                            "methods" => Ok(GeneratedField::Methods),
                            "generateOmittedAsInternal" | "generate_omitted_as_internal" => Ok(GeneratedField::GenerateOmittedAsInternal),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = SelectiveGapicGeneration;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct google.api.SelectiveGapicGeneration")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<SelectiveGapicGeneration, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut methods__ = None;
                let mut generate_omitted_as_internal__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Methods => {
                            if methods__.is_some() {
                                return Err(serde::de::Error::duplicate_field("methods"));
                            }
                            methods__ = Some(map_.next_value()?);
                        }
                        GeneratedField::GenerateOmittedAsInternal => {
                            if generate_omitted_as_internal__.is_some() {
                                return Err(serde::de::Error::duplicate_field("generateOmittedAsInternal"));
                            }
                            generate_omitted_as_internal__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(SelectiveGapicGeneration {
                    methods: methods__.unwrap_or_default(),
                    generate_omitted_as_internal: generate_omitted_as_internal__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("google.api.SelectiveGapicGeneration", FIELDS, GeneratedVisitor)
    }
}
