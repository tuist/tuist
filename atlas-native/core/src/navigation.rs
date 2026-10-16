use core::ffi::CStr;

pub struct Section {
    pub id: &'static str,
    pub title: &'static CStr,
    pub description: &'static CStr,
    pub url: &'static CStr,
    pub screen: &'static CStr,
    pub key: &'static CStr,
    pub group: &'static CStr,
    pub shortcut: bool,
    pub scope: &'static CStr,
}

pub struct Group {
    pub title: &'static CStr,
    pub description: &'static CStr,
    pub id: &'static CStr,
    pub parent: &'static CStr,
    pub placement: &'static CStr,
}

const fn text(bytes: &'static [u8]) -> &'static CStr {
    match CStr::from_bytes_with_nul(bytes) {
        Ok(value) => value,
        Err(_) => panic!("invalid catalog string"),
    }
}

macro_rules! section {
    ($id:literal, $title:literal, $description:literal, $path:literal, $group:literal, $screen:literal, $shortcut:expr, $scope:literal) => {
        Section {
            id: $id,
            key: text(concat!($id, "\0").as_bytes()),
            title: text(concat!($title, "\0").as_bytes()),
            description: text(concat!($description, "\0").as_bytes()),
            url: text(concat!("https://atlas.tuist.dev", $path, "\0").as_bytes()),
            screen: text(concat!($screen, "\0").as_bytes()),
            group: text(concat!($group, "\0").as_bytes()),
            shortcut: $shortcut,
            scope: text(concat!($scope, "\0").as_bytes()),
        }
    };
}

macro_rules! group {
    ($id:literal, $title:literal, $description:literal, $parent:literal, $placement:literal) => {
        Group {
            id: text(concat!($id, "\0").as_bytes()),
            title: text(concat!($title, "\0").as_bytes()),
            description: text(concat!($description, "\0").as_bytes()),
            parent: text(concat!($parent, "\0").as_bytes()),
            placement: text(concat!($placement, "\0").as_bytes()),
        }
    };
}

pub static GROUPS: &[Group] = &[
    group!(
        "overview",
        "Overview",
        "Company overview and team work",
        "",
        "workspace"
    ),
    group!(
        "commercial",
        "Commercial",
        "Sales, finance, go-to-market, and support",
        "",
        "workspace"
    ),
    group!(
        "outbound",
        "Outbound",
        "Email campaigns and postal correspondence",
        "",
        "workspace"
    ),
    group!(
        "engineering",
        "Engineering",
        "Projects, domains, errors, postmortems, and specs",
        "",
        "workspace"
    ),
    group!(
        "people",
        "People",
        "Employee services and time off",
        "",
        "workspace"
    ),
    group!(
        "operations",
        "Operations",
        "Hardware, data centers, insurance, and financing",
        "",
        "workspace"
    ),
    group!(
        "library",
        "Library",
        "Shared documents and notes",
        "",
        "workspace"
    ),
    group!(
        "admin",
        "Admin",
        "Access, audit, agents, and inference",
        "",
        "workspace"
    ),
    group!(
        "sales",
        "Sales",
        "Accounts, feature interest, licenses, and proofs of concept",
        "commercial",
        "workspace"
    ),
    group!(
        "finance",
        "Finance",
        "Financial overview and vendor costs",
        "commercial",
        "workspace"
    ),
    group!(
        "gtm",
        "GTM",
        "Content, outreach, and social",
        "commercial",
        "workspace"
    ),
    group!(
        "hardware",
        "Hardware",
        "Assets and infrastructure operations",
        "operations",
        "workspace"
    ),
    group!(
        "settings",
        "Settings",
        "Personal preferences and connected accounts",
        "",
        "settings"
    ),
];

// Preserve the original five indices and fields 0–3 for existing C/JNI callers.
pub static SECTIONS: &[Section] = &[
    section!(
        "accounts",
        "Accounts",
        "Customer relationships and sales",
        "/commercial/sales/accounts",
        "sales",
        "browser",
        false,
        ""
    ),
    section!(
        "tasks",
        "Tasks",
        "Your team's work and reminders",
        "/tasks",
        "overview",
        "browser",
        true,
        ""
    ),
    section!(
        "notes",
        "Notes",
        "Shared knowledge and documents",
        "/library/notes",
        "library",
        "browser",
        false,
        ""
    ),
    section!(
        "ai-providers",
        "AI accounts",
        "Connect your personal Claude and ChatGPT accounts",
        "/settings/llm-providers",
        "settings",
        "browser",
        false,
        ""
    ),
    section!(
        "time-off",
        "Time off",
        "Request holidays and see your leave history",
        "/people/time-off",
        "people",
        "time-off",
        true,
        ""
    ),
    section!(
        "tuist",
        "Tuist",
        "Company activity and overview",
        "/",
        "overview",
        "browser",
        false,
        ""
    ),
    section!(
        "sales",
        "Sales overview",
        "Sales pipeline and performance",
        "/commercial/sales",
        "sales",
        "browser",
        false,
        ""
    ),
    section!(
        "feature-interests",
        "Feature interest",
        "Customer interest and product opportunities",
        "/commercial/sales/feature-interests",
        "sales",
        "browser",
        false,
        ""
    ),
    section!(
        "licenses",
        "Licenses",
        "Customer licenses and entitlements",
        "/commercial/sales/licenses",
        "sales",
        "browser",
        false,
        "licenses:read"
    ),
    section!(
        "pocs",
        "Proofs of concept",
        "Track customer evaluations",
        "/commercial/sales/pocs",
        "sales",
        "browser",
        false,
        ""
    ),
    section!(
        "finance",
        "Finance overview",
        "Revenue, costs, and financial performance",
        "/commercial/finance",
        "finance",
        "browser",
        false,
        "finance:read"
    ),
    section!(
        "vendors",
        "Vendor costs",
        "Vendor spending and commitments",
        "/commercial/finance/vendors",
        "finance",
        "browser",
        false,
        "finance:read"
    ),
    section!(
        "content",
        "Content",
        "Plan and publish go-to-market content",
        "/commercial/gtm/content",
        "gtm",
        "browser",
        false,
        ""
    ),
    section!(
        "outreach",
        "Outreach",
        "Contacts and outbound relationships",
        "/commercial/gtm/outreach",
        "gtm",
        "browser",
        false,
        ""
    ),
    section!(
        "social",
        "Social",
        "Social content and distribution",
        "/commercial/gtm/social",
        "gtm",
        "browser",
        false,
        ""
    ),
    section!(
        "support",
        "Support",
        "Customer conversations and support",
        "/commercial/support",
        "commercial",
        "browser",
        false,
        ""
    ),
    section!(
        "email",
        "Email",
        "Email campaigns, audiences, and mailboxes",
        "/outbound/email",
        "outbound",
        "browser",
        false,
        ""
    ),
    section!(
        "postal",
        "Postal",
        "Physical letters and correspondence",
        "/outbound/postal",
        "outbound",
        "browser",
        false,
        "letters:read"
    ),
    section!(
        "projects",
        "Projects",
        "Engineering projects and repositories",
        "/engineering/projects",
        "engineering",
        "browser",
        false,
        ""
    ),
    section!(
        "domains",
        "Domains",
        "Engineering domains and ownership",
        "/engineering/domains",
        "engineering",
        "browser",
        false,
        ""
    ),
    section!(
        "errors",
        "Errors",
        "Investigate application failures",
        "/engineering/errors",
        "engineering",
        "browser",
        false,
        ""
    ),
    section!(
        "postmortems",
        "Postmortems",
        "Incidents, learning, and follow-up",
        "/engineering/postmortems",
        "engineering",
        "browser",
        false,
        ""
    ),
    section!(
        "specs",
        "Specs",
        "Engineering proposals and specifications",
        "/engineering/specs",
        "engineering",
        "browser",
        false,
        ""
    ),
    section!(
        "hardware",
        "Assets",
        "Hardware inventory and infrastructure",
        "/operations/hardware",
        "hardware",
        "browser",
        false,
        "assets:read"
    ),
    section!(
        "data-centers",
        "Data centers",
        "Infrastructure sites and racks",
        "/operations/hardware/data-centers",
        "hardware",
        "browser",
        false,
        "assets:read"
    ),
    section!(
        "insurance",
        "Insurance",
        "Hardware coverage and policies",
        "/operations/hardware/insurance",
        "hardware",
        "browser",
        false,
        "insurance:read"
    ),
    section!(
        "financings",
        "Financings",
        "Hardware financing agreements",
        "/operations/hardware/financings",
        "hardware",
        "browser",
        false,
        "assets:read"
    ),
    section!(
        "documents",
        "Documents",
        "Contracts and shared files",
        "/library/documents",
        "library",
        "browser",
        false,
        "documents:read"
    ),
    section!(
        "audit",
        "Audit",
        "Review recorded workspace activity",
        "/admin/audit",
        "admin",
        "browser",
        false,
        "admin:read"
    ),
    section!(
        "users",
        "Users",
        "Workspace users and membership",
        "/admin/users",
        "admin",
        "browser",
        false,
        "admin:read"
    ),
    section!(
        "roles",
        "Roles",
        "Roles and delegated permissions",
        "/admin/roles",
        "admin",
        "browser",
        false,
        "admin:read"
    ),
    section!(
        "mcps",
        "MCPs",
        "Manage connected tool servers",
        "/admin/mcps",
        "admin",
        "browser",
        false,
        "admin:read"
    ),
    section!(
        "sessions",
        "Sessions",
        "Agent sessions and conversations",
        "/admin/sessions",
        "admin",
        "browser",
        false,
        "admin:read"
    ),
    section!(
        "memory",
        "Memory",
        "Workspace knowledge and agent memory",
        "/admin/memory",
        "admin",
        "browser",
        false,
        "admin:read"
    ),
    section!(
        "inference",
        "Inference",
        "Inference providers, profiles, and usage",
        "/admin/inference",
        "admin",
        "browser",
        false,
        "admin:read"
    ),
];

pub fn field(section: i32, field: i32) -> Option<&'static CStr> {
    let section = SECTIONS.get(usize::try_from(section).ok()?)?;
    match field {
        0 => Some(section.title),
        1 => Some(section.description),
        2 => Some(section.url),
        3 => Some(section.screen),
        4 => Some(section.key),
        5 => Some(section.group),
        6 => Some(if section.shortcut { c"1" } else { c"0" }),
        7 => Some(section.scope),
        _ => None,
    }
}

pub fn group_field(group: i32, field: i32) -> Option<&'static CStr> {
    let group = GROUPS.get(usize::try_from(group).ok()?)?;
    match field {
        0 => Some(group.title),
        1 => Some(group.description),
        2 => Some(group.id),
        3 => Some(group.parent),
        4 => Some(group.placement),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sections_have_unique_destinations_and_stable_keys() {
        for (index, section) in SECTIONS.iter().enumerate() {
            assert_eq!(section.key.to_str().unwrap(), section.id);
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
                section
                    .id
                    .bytes()
                    .all(|b| b.is_ascii_lowercase() || b == b'-')
            );
            assert!(
                SECTIONS[..index]
                    .iter()
                    .all(|other| other.id != section.id && other.url != section.url)
            );
            assert!(GROUPS.iter().any(|group| group.id == section.group));
            assert!(!section.shortcut || section.group != c"settings");
        }
    }

    #[test]
    fn group_hierarchy_is_unique_reachable_and_acyclic() {
        for (index, group) in GROUPS.iter().enumerate() {
            assert!(!group.id.to_bytes().is_empty());
            assert!(GROUPS[..index].iter().all(|other| other.id != group.id));
            let mut parent = group.parent;
            let mut depth = 0;
            while !parent.to_bytes().is_empty() {
                let ancestor = GROUPS.iter().find(|other| other.id == parent).unwrap();
                assert_eq!(ancestor.placement, group.placement);
                parent = ancestor.parent;
                depth += 1;
                assert!(depth < GROUPS.len(), "catalog contains a cycle");
            }
            assert!(
                SECTIONS.iter().any(|section| section.group == group.id)
                    || GROUPS.iter().any(|child| child.parent == group.id)
            );
        }
        let roots: Vec<_> = GROUPS
            .iter()
            .filter(|g| g.parent == c"" && g.placement == c"workspace")
            .map(|g| g.id.to_str().unwrap())
            .collect();
        assert_eq!(
            roots,
            [
                "overview",
                "commercial",
                "outbound",
                "engineering",
                "people",
                "operations",
                "library",
                "admin"
            ]
        );
    }

    #[test]
    fn existing_abi_fields_and_shortcuts_are_preserved() {
        assert_eq!(
            SECTIONS[..5].iter().map(|s| s.id).collect::<Vec<_>>(),
            ["accounts", "tasks", "notes", "ai-providers", "time-off"]
        );
        assert_eq!(field(4, 3), Some(c"time-off"));
        assert_eq!(
            field(0, 2),
            Some(c"https://atlas.tuist.dev/commercial/sales/accounts")
        );
        assert_eq!(
            SECTIONS
                .iter()
                .filter(|s| s.shortcut)
                .map(|s| s.id)
                .collect::<Vec<_>>(),
            ["tasks", "time-off"]
        );
    }

    #[test]
    fn invalid_sections_groups_and_fields_are_rejected() {
        for index in [-1, i32::MAX] {
            assert!(field(index, 0).is_none());
            assert!(group_field(index, 0).is_none());
        }
        assert!(field(SECTIONS.len() as i32, 0).is_none());
        assert!(group_field(GROUPS.len() as i32, 0).is_none());
        for id in [-1, 8, i32::MAX] {
            assert!(field(0, id).is_none());
        }
        for id in [-1, 5, i32::MAX] {
            assert!(group_field(0, id).is_none());
        }
    }
}
