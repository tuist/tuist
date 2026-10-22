use crate::ffi::{atlas_section_count, atlas_section_field_byte, atlas_section_field_length};
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
            for field_id in 0..4 {
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
            Java_dev_tuist_atlas_AtlasCore_fieldByte(environment, instance, 0, 4, 0),
            -1
        );
    }
}
