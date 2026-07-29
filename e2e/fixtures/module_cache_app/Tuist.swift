import ProjectDescription

// e2e/module_cache_backward_compat.bats rewrites this file with the per-run
// project handle and the canary URL before running the suite.
let tuist = Tuist(
    fullHandle: "tuist/module-cache-backward-compat",
    url: "https://canary.tuist.dev"
)
