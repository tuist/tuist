# Home Activity Data

`HomeActivityRepository` uses the generated `HomeApi` through the existing authenticated Retrofit client. The server contract is `server/home-activity.md`.

Fetch each project-scoped section independently, with at most three results over seven days. Never approximate new flaky tests using last-run timestamps or scan history client-side. HTTP errors, old servers, and unsupported build systems are not empty successes.

Dashboard paths are relative to the deployment: preserve the complete configured server base path/port and reject foreign origins, other projects, query/fragment additions, and traversal. Native credentials belong only on API requests, never browser/share links. This repository adds no persistence, polling, or CI controls.

Repository tests live in `app/src/test/java/dev/tuist/app/data/home/`.
