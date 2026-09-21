impl serde::Serialize for SemVer {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.major != 0 {
            len += 1;
        }
        if self.minor != 0 {
            len += 1;
        }
        if self.patch != 0 {
            len += 1;
        }
        if !self.prerelease.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("build.bazel.semver.SemVer", len)?;
        if self.major != 0 {
            struct_ser.serialize_field("major", &self.major)?;
        }
        if self.minor != 0 {
            struct_ser.serialize_field("minor", &self.minor)?;
        }
        if self.patch != 0 {
            struct_ser.serialize_field("patch", &self.patch)?;
        }
        if !self.prerelease.is_empty() {
            struct_ser.serialize_field("prerelease", &self.prerelease)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for SemVer {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "major",
            "minor",
            "patch",
            "prerelease",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Major,
            Minor,
            Patch,
            Prerelease,
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
                            "major" => Ok(GeneratedField::Major),
                            "minor" => Ok(GeneratedField::Minor),
                            "patch" => Ok(GeneratedField::Patch),
                            "prerelease" => Ok(GeneratedField::Prerelease),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = SemVer;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct build.bazel.semver.SemVer")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<SemVer, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut major__ = None;
                let mut minor__ = None;
                let mut patch__ = None;
                let mut prerelease__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Major => {
                            if major__.is_some() {
                                return Err(serde::de::Error::duplicate_field("major"));
                            }
                            major__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Minor => {
                            if minor__.is_some() {
                                return Err(serde::de::Error::duplicate_field("minor"));
                            }
                            minor__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Patch => {
                            if patch__.is_some() {
                                return Err(serde::de::Error::duplicate_field("patch"));
                            }
                            patch__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Prerelease => {
                            if prerelease__.is_some() {
                                return Err(serde::de::Error::duplicate_field("prerelease"));
                            }
                            prerelease__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(SemVer {
                    major: major__.unwrap_or_default(),
                    minor: minor__.unwrap_or_default(),
                    patch: patch__.unwrap_or_default(),
                    prerelease: prerelease__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("build.bazel.semver.SemVer", FIELDS, GeneratedVisitor)
    }
}
