"""The CI-only `-Dwarnings` gate for Kura's first-party crates (see //:deny_warnings)."""

DENY_WARNINGS = select({
    "//:deny_warnings": ["-Dwarnings"],
    "//conditions:default": [],
})
