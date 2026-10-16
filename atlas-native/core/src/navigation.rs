use core::ffi::CStr;

pub struct Section {
    pub id: &'static str,
    pub title: &'static CStr,
    pub description: &'static CStr,
    pub url: &'static CStr,
    pub screen: &'static CStr,
}

pub static SECTIONS: &[Section] = &[
    Section {
        id: "accounts",
        title: c"Accounts",
        description: c"Customer relationships and sales",
        url: c"https://atlas.tuist.dev/commercial/sales/accounts",
        screen: c"browser",
    },
    Section {
        id: "tasks",
        title: c"Tasks",
        description: c"Your team's work and reminders",
        url: c"https://atlas.tuist.dev/tasks",
        screen: c"browser",
    },
    Section {
        id: "notes",
        title: c"Notes",
        description: c"Shared knowledge and documents",
        url: c"https://atlas.tuist.dev/library/notes",
        screen: c"browser",
    },
    Section {
        id: "ai-providers",
        title: c"AI accounts",
        description: c"Connect your personal Claude and ChatGPT accounts",
        url: c"https://atlas.tuist.dev/settings/llm-providers",
        screen: c"browser",
    },
    Section {
        id: "time-off",
        title: c"Time off",
        description: c"Request holidays and see your leave history",
        url: c"https://atlas.tuist.dev/people/time-off",
        screen: c"time-off",
    },
];

pub fn field(section: i32, field: i32) -> Option<&'static CStr> {
    let section = SECTIONS.get(usize::try_from(section).ok()?)?;
    match field {
        0 => Some(section.title),
        1 => Some(section.description),
        2 => Some(section.url),
        3 => Some(section.screen),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sections_have_unique_https_destinations_and_utf8_content() {
        for (index, section) in SECTIONS.iter().enumerate() {
            assert!(!section.title.to_str().unwrap().is_empty());
            assert!(!section.description.to_str().unwrap().is_empty());
            assert!(
                section
                    .url
                    .to_str()
                    .unwrap()
                    .starts_with("https://atlas.tuist.dev/")
            );
            assert!(
                SECTIONS[..index]
                    .iter()
                    .all(|other| other.url != section.url)
            );
        }
    }

    #[test]
    fn section_ids_are_unique_and_shell_friendly() {
        for (index, section) in SECTIONS.iter().enumerate() {
            assert!(!section.id.is_empty());
            assert!(
                section
                    .id
                    .bytes()
                    .all(|byte| byte.is_ascii_lowercase() || byte == b'-')
            );
            assert!(SECTIONS[..index].iter().all(|other| other.id != section.id));
        }
    }

    #[test]
    fn section_titles_match_the_dashboard() {
        let titles: Vec<_> = SECTIONS
            .iter()
            .map(|section| section.title.to_str().unwrap())
            .collect();
        assert_eq!(
            titles,
            ["Accounts", "Tasks", "Notes", "AI accounts", "Time off"]
        );
        assert_eq!(field(4, 3), Some(c"time-off"));
        assert_eq!(field(0, 3), Some(c"browser"));
    }

    #[test]
    fn destinations_match_the_atlas_dashboard_routes() {
        let urls: Vec<_> = SECTIONS
            .iter()
            .map(|section| section.url.to_str().unwrap())
            .collect();
        assert_eq!(
            urls,
            [
                "https://atlas.tuist.dev/commercial/sales/accounts",
                "https://atlas.tuist.dev/tasks",
                "https://atlas.tuist.dev/library/notes",
                "https://atlas.tuist.dev/settings/llm-providers",
                "https://atlas.tuist.dev/people/time-off",
            ]
        );
    }

    #[test]
    fn invalid_sections_and_fields_are_rejected() {
        for section in [-1, SECTIONS.len() as i32, i32::MAX] {
            assert!(field(section, 0).is_none());
        }
        for field_id in [-1, 4, i32::MAX] {
            assert!(field(0, field_id).is_none());
        }
    }
}
