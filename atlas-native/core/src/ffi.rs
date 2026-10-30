use crate::navigation::{GROUPS, SECTIONS, field, group_field};
use core::ffi::c_char;

#[unsafe(no_mangle)]
pub extern "C" fn atlas_section_count() -> i32 {
    SECTIONS.len() as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn atlas_section_field(section: i32, field_id: i32) -> *const c_char {
    field(section, field_id).map_or(core::ptr::null(), |value| value.as_ptr())
}

#[unsafe(no_mangle)]
pub extern "C" fn atlas_section_field_length(section: i32, field_id: i32) -> i32 {
    field(section, field_id).map_or(-1, |value| value.to_bytes().len() as i32)
}

#[unsafe(no_mangle)]
pub extern "C" fn atlas_section_field_byte(section: i32, field_id: i32, offset: i32) -> i32 {
    let Ok(offset) = usize::try_from(offset) else {
        return -1;
    };
    field(section, field_id)
        .and_then(|value| value.to_bytes().get(offset))
        .map_or(-1, |value| i32::from(*value))
}

#[unsafe(no_mangle)]
pub extern "C" fn atlas_group_count() -> i32 {
    GROUPS.len() as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn atlas_group_field(group: i32, field_id: i32) -> *const c_char {
    group_field(group, field_id).map_or(core::ptr::null(), |value| value.as_ptr())
}

#[unsafe(no_mangle)]
pub extern "C" fn atlas_group_field_length(group: i32, field_id: i32) -> i32 {
    group_field(group, field_id).map_or(-1, |value| value.to_bytes().len() as i32)
}

#[unsafe(no_mangle)]
pub extern "C" fn atlas_group_field_byte(group: i32, field_id: i32, offset: i32) -> i32 {
    let Ok(offset) = usize::try_from(offset) else {
        return -1;
    };
    group_field(group, field_id)
        .and_then(|value| value.to_bytes().get(offset))
        .map_or(-1, |value| i32::from(*value))
}

#[unsafe(no_mangle)]
pub extern "C" fn atlas_destination_count() -> i32 {
    crate::destinations::DESTINATIONS.len() as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn atlas_destination_field(destination: i32, field: i32) -> *const c_char {
    crate::destinations::field(destination, field).map_or(core::ptr::null(), |value| value.as_ptr())
}

#[unsafe(no_mangle)]
pub extern "C" fn atlas_destination_field_length(destination: i32, field: i32) -> i32 {
    crate::destinations::field(destination, field).map_or(-1, |value| value.to_bytes().len() as i32)
}

#[unsafe(no_mangle)]
pub extern "C" fn atlas_destination_field_byte(destination: i32, field: i32, offset: i32) -> i32 {
    let Ok(offset) = usize::try_from(offset) else {
        return -1;
    };
    crate::destinations::field(destination, field)
        .and_then(|value| value.to_bytes().get(offset))
        .map_or(-1, |value| i32::from(*value))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn byte_bridge_matches_every_c_string() {
        assert_eq!(atlas_section_count(), SECTIONS.len() as i32);
        for section in 0..atlas_section_count() {
            for field_id in 0..8 {
                let value = field(section, field_id).unwrap();
                assert_eq!(atlas_section_field(section, field_id), value.as_ptr());
                let length = atlas_section_field_length(section, field_id);
                let bytes: Vec<_> = (0..length)
                    .map(|offset| atlas_section_field_byte(section, field_id, offset) as u8)
                    .collect();
                assert_eq!(bytes, value.to_bytes());
                assert_eq!(atlas_section_field_byte(section, field_id, length), -1);
            }
        }
    }

    #[test]
    fn group_bridge_matches_strings_and_rejects_invalid_inputs() {
        for group in 0..atlas_group_count() {
            for id in 0..5 {
                let value = group_field(group, id).unwrap();
                assert_eq!(atlas_group_field(group, id), value.as_ptr());
                let len = atlas_group_field_length(group, id);
                let bytes: Vec<_> = (0..len)
                    .map(|i| atlas_group_field_byte(group, id, i) as u8)
                    .collect();
                assert_eq!(bytes, value.to_bytes());
                assert_eq!(atlas_group_field_byte(group, id, len), -1);
            }
        }
        for (group, id) in [(-1, 0), (atlas_group_count(), 0), (0, -1), (0, 5)] {
            assert!(atlas_group_field(group, id).is_null());
            assert_eq!(atlas_group_field_length(group, id), -1);
            assert_eq!(atlas_group_field_byte(group, id, 0), -1);
        }
        assert_eq!(atlas_group_field_byte(0, 0, -1), -1);
        assert_eq!(atlas_group_field_byte(0, 0, i32::MAX), -1);
    }

    #[test]
    fn invalid_bridge_inputs_do_not_panic_or_return_pointers() {
        for (section, field_id) in [(-1, 0), (i32::MAX, 0), (0, -1), (0, 8)] {
            assert!(atlas_section_field(section, field_id).is_null());
            assert_eq!(atlas_section_field_length(section, field_id), -1);
            assert_eq!(atlas_section_field_byte(section, field_id, 0), -1);
        }
        for offset in [-1, i32::MAX] {
            assert_eq!(atlas_section_field_byte(0, 0, offset), -1);
        }
    }
}
