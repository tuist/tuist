use crate::navigation::{SECTIONS, field};
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn byte_bridge_matches_every_c_string() {
        assert_eq!(atlas_section_count(), SECTIONS.len() as i32);
        for section in 0..atlas_section_count() {
            for field_id in 0..3 {
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
    fn invalid_bridge_inputs_do_not_panic_or_return_pointers() {
        for (section, field_id) in [(-1, 0), (i32::MAX, 0), (0, -1), (0, 3)] {
            assert!(atlas_section_field(section, field_id).is_null());
            assert_eq!(atlas_section_field_length(section, field_id), -1);
            assert_eq!(atlas_section_field_byte(section, field_id, 0), -1);
        }
        for offset in [-1, i32::MAX] {
            assert_eq!(atlas_section_field_byte(0, 0, offset), -1);
        }
    }
}
