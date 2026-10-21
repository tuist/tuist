//! Native deep-link capabilities. Platform adapters parse URLs; this catalog is
//! the allowlist, not authorization and never an arbitrary API path resolver.
use core::ffi::CStr;

pub struct Destination {
    pub screen: &'static CStr,
    pub records: bool,
}

pub static DESTINATIONS: &[Destination] = &[
    Destination {
        screen: c"tasks",
        records: true,
    },
    Destination {
        screen: c"accounts",
        records: true,
    },
    Destination {
        screen: c"invoices",
        records: true,
    },
    Destination {
        screen: c"time-off",
        records: false,
    },
    Destination {
        screen: c"people",
        records: false,
    },
    Destination {
        screen: c"profile",
        records: false,
    },
];

pub fn field(destination: i32, field: i32) -> Option<&'static CStr> {
    let destination = DESTINATIONS.get(usize::try_from(destination).ok()?)?;
    match field {
        0 => Some(destination.screen),
        1 => Some(if destination.records { c"1" } else { c"0" }),
        2 => web_path(destination.screen),
        3 => Some(match destination.screen {
            screen if screen == c"accounts" => c"/commercial/sales/accounts",
            screen if screen == c"tasks" => c"/open/tasks",
            screen if screen == c"invoices" => c"/open/invoices",
            _ => c"",
        }),
        _ => None,
    }
}

fn web_path(screen: &CStr) -> Option<&'static CStr> {
    if screen == c"profile" {
        return Some(c"/settings");
    }
    let section = crate::navigation::SECTIONS
        .iter()
        .find(|section| section.screen == screen)?;
    let path = section
        .url
        .to_bytes_with_nul()
        .strip_prefix(b"https://atlas.tuist.dev")?;
    CStr::from_bytes_with_nul(path).ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::navigation::SECTIONS;
    use std::collections::HashSet;

    #[test]
    fn capabilities_are_unique_and_native() {
        let mut screens = HashSet::new();
        for destination in DESTINATIONS {
            assert!(screens.insert(destination.screen));
            if destination.screen != c"profile" {
                assert_eq!(
                    SECTIONS
                        .iter()
                        .filter(|section| section.screen == destination.screen)
                        .count(),
                    1
                );
            }
            assert_eq!(
                destination.records,
                [c"tasks", c"accounts", c"invoices"].contains(&destination.screen)
            );
        }
        assert!(field(-1, 0).is_none());
        assert!(field(DESTINATIONS.len() as i32, 0).is_none());
        assert!(field(0, 4).is_none());
        let paths: Vec<_> = (0..DESTINATIONS.len() as i32)
            .map(|index| field(index, 2).unwrap())
            .collect();
        assert_eq!(
            paths,
            [
                c"/tasks",
                c"/commercial/sales/accounts",
                c"/commercial/finance",
                c"/people/time-off",
                c"/people",
                c"/settings"
            ]
        );
        assert_eq!(paths.iter().collect::<HashSet<_>>().len(), paths.len());
    }
}
