---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Run only the tests affected by your latest changes with Tuist Selective Testing, so continuous integration lands feedback in seconds."
}
---
# Selective testing {#selective-testing}

As projects grow, running every test on every push stops being viable. Tuist Selective Testing drastically reduces test time by running only the tests affected by what changed since the last successful run, using our <.localized_link href="/guides/features/projects/hashing">hashing algorithm</.localized_link>.

## Supported build systems {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

Support for other build systems is planned.
