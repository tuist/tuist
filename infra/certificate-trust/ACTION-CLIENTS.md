# Action and CI wrapper transport ownership

Source audit at `7ce73ee6abc0109e1ccce271c4fbd3f448e5d7f3` on the remediation branch. This records C12 ownership, not qualification of separately published actions, installed executables or CI-provider runtimes.

## Local entrypoints

| Entrypoint | Actual network owner | Result and remaining gate |
| --- | --- | --- |
| `.github/actions/install` | Installed `tuist install`; `actions/cache@v4` for the GitHub archive backend; `tuist/cache-volume@v1` for the volume backend | The local Node/shell preparation computes paths and keys, then invokes the existing CLI. It does not download or upgrade that CLI. Shared CLI and delegated SwiftPM/Git qualifications remain C03/C04/C15; GitHub's archive action/runtime and the exact resolved external action revisions are independent. |
| `.github/actions/cache-volume` and `ci/cache-volume/{buildkite,gitlab}` | Preinstalled `tuist-cache-volume` | Thin argument-validation wrappers. No binary download or independent TLS verifier. The helper and image that install it remain C13; downloading the Buildkite plugin/GitLab remote template is owned by the CI executor. |
| `.github/actions/{xcode-cache,module-cache}` and their `ci/runner-caches` equivalents | Preinstalled `tuist-runner-cache`, host cache agent and their image | Thin activation wrappers. The shared activation scripts are kept identical, and unsupported/unavailable caches warn without enabling caching. Helper, host and transfer paths remain C13. |
| `.github/actions/gradle-cache` and `ci/runner-caches/gradle-cache` | Preinstalled volume client; subsequent Gradle/JVM dependency downloads | Attaches the volume and installs the cleanup init script; no independent TLS client is introduced. C13 owns the installed helper, C07 the Tuist Gradle plugin, and C15 the remaining Gradle/JVM/provider transports. |

This is a bounded inventory of these local packages, not all workflows, shell/curl installers, downloaded executables or Node processes in the repository. In particular, an action tag in this checkout does not establish the content or trust behavior of the separately released action or provider downloading it.

## Validation

The following local contract suites passed together (`/tmp/tuist-emudhra-audit/c12-wrapper-contract-tests.log`):

```sh
node --test .github/actions/install/action.test.mjs
bash .github/actions/cache-volume/action_test.sh
bash .github/actions/xcode-cache/action_test.sh
bash .github/actions/module-cache/action_test.sh
bash .github/actions/gradle-cache/action_test.sh
bash ci/cache-volume/integrations_test.sh
bash ci/runner-caches/integrations_test.sh
```

The install suite reports 15 passing tests. Shell contracts cover literal argument forwarding, fail-before-attachment validation, version/capability negotiation, standalone packaging, provider equivalents, and the intended cache-failure/cold-job behavior. They use local stubs, not TLS servers: **they are not certificate-negative tests or evidence that the installed helper is patched**.

## Release and runtime gates

Do not add a downloader, TLS fallback, host trust mutation or new certificate store to these wrappers to compensate for an old helper. Independently qualify and release the actual installed CLI/helper and each relevant CI executor/runtime. Record exact resolved action/plugin/template revisions and installed artifact hashes. Preserve cold-job behavior, literal arguments, token isolation, cache contents and warm replacement constraints. A certificate failure must not cause the helper to retry through a weaker network transport.
