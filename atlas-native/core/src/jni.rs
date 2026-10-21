use crate::ffi::{
    atlas_group_count, atlas_group_field_byte, atlas_group_field_length, atlas_section_count,
    atlas_section_field_byte, atlas_section_field_length,
};
use core::ffi::c_void;

// Primitive-only JNI calls avoid Java heap ownership and keep the small UTF-8
// catalog dependency-free. No environment or object pointers are dereferenced.
#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_tuist_atlas_AtlasCore_sectionCount(
    _environment: *mut c_void,
    _instance: *mut c_void,
) -> i32 {
    atlas_section_count()
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_tuist_atlas_AtlasCore_fieldLength(
    _environment: *mut c_void,
    _instance: *mut c_void,
    section: i32,
    field_id: i32,
) -> i32 {
    atlas_section_field_length(section, field_id)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_tuist_atlas_AtlasCore_fieldByte(
    _environment: *mut c_void,
    _instance: *mut c_void,
    section: i32,
    field_id: i32,
    offset: i32,
) -> i32 {
    atlas_section_field_byte(section, field_id, offset)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_tuist_atlas_AtlasCore_groupCount(
    _environment: *mut c_void,
    _instance: *mut c_void,
) -> i32 {
    atlas_group_count()
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_tuist_atlas_AtlasCore_groupFieldLength(
    _environment: *mut c_void,
    _instance: *mut c_void,
    group: i32,
    field_id: i32,
) -> i32 {
    atlas_group_field_length(group, field_id)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_tuist_atlas_AtlasCore_groupFieldByte(
    _environment: *mut c_void,
    _instance: *mut c_void,
    group: i32,
    field_id: i32,
    offset: i32,
) -> i32 {
    atlas_group_field_byte(group, field_id, offset)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_tuist_atlas_AtlasCore_destinationCount(
    _environment: *mut c_void,
    _instance: *mut c_void,
) -> i32 {
    crate::ffi::atlas_destination_count()
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_tuist_atlas_AtlasCore_destinationFieldLength(
    _environment: *mut c_void,
    _instance: *mut c_void,
    destination: i32,
    field: i32,
) -> i32 {
    crate::ffi::atlas_destination_field_length(destination, field)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_tuist_atlas_AtlasCore_destinationFieldByte(
    _environment: *mut c_void,
    _instance: *mut c_void,
    destination: i32,
    field: i32,
    offset: i32,
) -> i32 {
    crate::ffi::atlas_destination_field_byte(destination, field, offset)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn jni_catalog_matches_the_shared_core_without_dereferencing_vm_pointers() {
        let environment = core::ptr::null_mut();
        let instance = core::ptr::null_mut();
        let count = Java_dev_tuist_atlas_AtlasCore_sectionCount(environment, instance);
        assert_eq!(count, atlas_section_count());
        for section in 0..count {
            for field_id in 0..8 {
                let length = Java_dev_tuist_atlas_AtlasCore_fieldLength(
                    environment,
                    instance,
                    section,
                    field_id,
                );
                assert_eq!(length, atlas_section_field_length(section, field_id));
                for offset in 0..length {
                    assert_eq!(
                        Java_dev_tuist_atlas_AtlasCore_fieldByte(
                            environment,
                            instance,
                            section,
                            field_id,
                            offset,
                        ),
                        atlas_section_field_byte(section, field_id, offset),
                    );
                }
            }
        }
    }

    #[test]
    fn jni_groups_match_c_bridge_and_reject_invalid_indices() {
        let env = core::ptr::null_mut();
        let instance = core::ptr::null_mut();
        assert_eq!(
            Java_dev_tuist_atlas_AtlasCore_groupCount(env, instance),
            atlas_group_count()
        );
        for group in 0..atlas_group_count() {
            for id in 0..5 {
                let length =
                    Java_dev_tuist_atlas_AtlasCore_groupFieldLength(env, instance, group, id);
                assert_eq!(length, atlas_group_field_length(group, id));
                for offset in 0..length {
                    assert_eq!(
                        Java_dev_tuist_atlas_AtlasCore_groupFieldByte(
                            env, instance, group, id, offset
                        ),
                        atlas_group_field_byte(group, id, offset)
                    );
                }
            }
        }
        for (group, id) in [(-1, 0), (atlas_group_count(), 0), (0, 5)] {
            assert_eq!(
                Java_dev_tuist_atlas_AtlasCore_groupFieldLength(env, instance, group, id),
                -1
            );
            assert_eq!(
                Java_dev_tuist_atlas_AtlasCore_groupFieldByte(env, instance, group, id, 0),
                -1
            );
        }
        assert_eq!(
            Java_dev_tuist_atlas_AtlasCore_groupFieldByte(env, instance, 0, 0, -1),
            -1
        );
    }

    #[test]
    fn destination_bridge_matches_c_and_rejects_invalid_indices() {
        use crate::ffi::*;
        let env = core::ptr::null_mut();
        let instance = core::ptr::null_mut();
        assert_eq!(
            Java_dev_tuist_atlas_AtlasCore_destinationCount(env, instance),
            atlas_destination_count()
        );
        for destination in 0..atlas_destination_count() {
            for field in 0..2 {
                let expected = crate::destinations::field(destination, field).unwrap();
                assert_eq!(
                    atlas_destination_field(destination, field),
                    expected.as_ptr()
                );
                let len = Java_dev_tuist_atlas_AtlasCore_destinationFieldLength(
                    env,
                    instance,
                    destination,
                    field,
                );
                let bytes: Vec<_> = (0..len)
                    .map(|offset| {
                        Java_dev_tuist_atlas_AtlasCore_destinationFieldByte(
                            env,
                            instance,
                            destination,
                            field,
                            offset,
                        ) as u8
                    })
                    .collect();
                assert_eq!(bytes, expected.to_bytes());
                assert_eq!(atlas_destination_field_byte(destination, field, len), -1);
            }
        }
        for (destination, field) in [(-1, 0), (atlas_destination_count(), 0), (0, -1), (0, 2)] {
            assert!(atlas_destination_field(destination, field).is_null());
            assert_eq!(
                Java_dev_tuist_atlas_AtlasCore_destinationFieldLength(
                    env,
                    instance,
                    destination,
                    field
                ),
                -1
            );
            assert_eq!(
                Java_dev_tuist_atlas_AtlasCore_destinationFieldByte(
                    env,
                    instance,
                    destination,
                    field,
                    0
                ),
                -1
            );
        }
        assert_eq!(atlas_destination_field_byte(0, 0, -1), -1);
        assert_eq!(atlas_destination_field_byte(0, 0, i32::MAX), -1);
    }

    #[test]
    fn jni_rejects_invalid_indices() {
        let environment = core::ptr::null_mut();
        let instance = core::ptr::null_mut();
        assert_eq!(
            Java_dev_tuist_atlas_AtlasCore_fieldLength(environment, instance, -1, 0),
            -1
        );
        assert_eq!(
            Java_dev_tuist_atlas_AtlasCore_fieldByte(environment, instance, 0, 0, -1),
            -1
        );
        assert_eq!(
            Java_dev_tuist_atlas_AtlasCore_fieldByte(environment, instance, 0, 8, 0),
            -1
        );
    }
}
