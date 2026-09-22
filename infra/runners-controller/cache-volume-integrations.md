# Cache volume integrations

The supported launch interface is a dedicated `tuist/cache-volume@v1` GitHub
Action. Its source, executable wrapper, tests and distributable package live in
`.github/actions/cache-volume`; `.github/workflows/cache-volume-action.yml`
validates the package on PRs and releases it independently from the server.
The first public tag is a rollout deliverable, after the Ceph/Kata smoke gates
in [cache-volumes.md](cache-volumes.md). A release requires the distribution
repository, a `main` branch, and the release token's write access. This PR does
not advertise Buildkite or GitLab volume support before their adapters exist.

## One storage service, provider-specific entry points

All providers should use the same private per-job clone, 20 GB default, seven-day
idle expiry, clear-generation fence, teardown checks and dashboard. Each entry
point attaches directories before dependency tools run. Saving is a server/agent
operation after a successful eligible job and writer teardown; no shell hook is
allowed to declare its own cache publication eligibility.

| Provider | Workflow interface | Current state |
| --- | --- | --- |
| GitHub Actions | `tuist/cache-volume@v1`, `key` and `path`, `cache-hit` output | Allocation and execution implemented; standalone release packaging included. Public release and live storage validation remain rollout gates. |
| Buildkite | `tuist/cache-volume#v1` plugin (`tuist/cache-volume-buildkite-plugin`), with a list of key/path pairs | Design below; server identity adapter and plugin not implemented. |
| GitLab CI | `tuist-cache-volume --key … --path …` in `before_script`, followed by a reusable template/component | Design below; server identity adapter not implemented. Existing `cache:` remains supported archive caching. |

Keep Linux as the initial platform for all three. Provider support and macOS
support are separate workstreams. Do not share cache namespaces between CI
providers automatically, even if repository URLs look equivalent.

## GitHub Action distribution

Publish `action.yml`, `attach.sh`, `README.md`, `LICENSE.md` and `SOURCE_COMMIT` at
the root of `tuist/cache-volume`. The composite action uses `github.action_path`
to find its wrapper, so it works without checking out the Tuist monorepo. Inputs
travel through environment variables and quoted arguments. The wrapper locates
the preinstalled native or GitHub job-container client; it downloads no mutable
binary and needs no extra workflow credentials.

The release workflow is manual, restricted to the monorepo's `main`, and accepts
an immutable `v1.x.y` tag. It runs package tests before publishing; existing
version tags are rejected, while `v1` advances in the same atomic push. This
keeps action releases independent of server versioning. Consumers may pin the
release commit. PR builds export the same package for review before release.

Before first release, run native and container cold/warm smoke jobs using the
reviewed action commit. Confirm output propagation through the actual composite
step as well as fallback behavior. Publish v1 only with the fleet rollout; the
presence of packaging tests is not evidence of live Ceph or Kata compatibility.

## Buildkite: a plugin

Proposed pipeline syntax (not available yet):

```yaml
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: gradle-dependencies
              path: .gradle
    env:
      GRADLE_USER_HOME: .gradle
    command: ./gradlew test
```

Use a `pre-command` plugin hook: checkout is complete and dependency commands
have not started. Parse and validate a list of key/path pairs, then call the
same installed client. Do not use a post-command hook to save the volume:
background writers may still exist and later hooks can fail the job. A hit is
observable in the job log and Tuist dashboard; any optional metadata should be
namespaced by job UUID and volume key to avoid parallel steps overwriting it.
Buildkite's [plugin hook model](https://buildkite.com/docs/pipelines/integrations/plugins)
and [hook ordering](https://buildkite.com/docs/agent/hooks) support this entry point.

Native jobs inherit the existing pod mount. Docker-plugin jobs require an
explicit tested mapping of the job's private `_tuist_cache` root at the same
absolute path inside the command container: the attached target is a symlink,
so mounting only the checkout or cache target is insufficient. Attach before
the Docker plugin's command hook starts its container. Preserve the execution
UID scope; do not reuse a host-user-owned clone for a different container user.
Document the Docker-plugin configuration separately after proving it with DinD;
GitHub's `/__w` mapping does not establish Buildkite container compatibility.

The backend work is more than removing `provider == "github"`:

- Resolve the actual executed session to the account-owned Buildkite job UUID
  and pipeline, using `Buildkite.Job` and the existing server-side API client.
  The lifecycle `repository` currently means the pipeline slug, not a GitHub
  repository ID. Persist an immutable pipeline identifier and repository
  identity; invalidate the scope if a pipeline is repointed to another repo.
- Fetch authoritative branch, source/PR and pipeline-default-branch metadata.
  The existing `Buildkite.job_trusted?/2` excludes some forks but does not enforce
  default-branch publication. Its environment-based predicate is insufficient
  for this policy. Do not authorize from plugin inputs or mutable job variables.
- The [pipeline API](https://buildkite.com/docs/apis/rest-api/pipelines) exposes
  repository and default branch. Confirm whether the configured Agent Stack
  credential can supply all required authoritative fields; otherwise add a
  narrowly scoped server-side read integration. This credential question is an
  implementation prerequisite, not an assumption that the current token works.
- Reuse recorded job completion and pod teardown, including failed/cancelled
  jobs. Only successful, verified default-branch non-PR jobs may publish.
  Unknown identity must refuse attachment; unknown writer eligibility must
  never promote a snapshot.

## GitLab: explicit directory attachment first

Proposed initial syntax after its identity adapter ships:

```yaml
test:
  tags: [tuist-linux]
  variables:
    GRADLE_USER_HOME: "$CI_PROJECT_DIR/.gradle"
  before_script:
    - tuist-cache-volume --key gradle-dependencies --path .gradle
  script:
    - ./gradlew test
```

Tuist's executor embeds GitLab Runner's **shell executor** inside the isolated
runner. The installed binary is available there; a job-level `image:` does not
turn this implementation into GitLab's Docker executor. Arbitrary Docker child
containers need explicit private-root mounts just as Buildkite does.

Keep `cache:` independent. GitLab's cache restores archives before
`before_script`, and artifacts can restore into the same paths. Either would
make the volume attachment reject a nonempty directory. Users should remove
only overlapping archive/artifact paths, retaining unrelated cache entries.
Automatically reinterpreting `cache:` would change fallback keys, pull/push
policies, wildcard paths and archive semantics. Existing Tuist multipart archive
caching continues to handle it. See [GitLab caching](https://docs.gitlab.com/ci/caching/).

A versioned include can provide a hidden job or reusable attachment snippet,
with explicit composition into an existing `before_script`; do not silently
replace the user's setup commands. A Catalog component is a convenience layer,
not a requirement: [components must be hosted on the same GitLab instance](https://docs.gitlab.com/ci/components/),
so GitLab.com distribution alone would exclude self-managed installations. Keep
the direct command working everywhere and support mirroring the template.

Backend prerequisites:

- Resolve the job from the executed session and stored acquired assignment.
  Scope identity by account, provider, canonical instance URL, immutable project
  ID, key, architecture and UID. Project IDs alone collide across instances;
  project paths can change. Preserve a verified identity before the encrypted
  assignment is purged on completion.
- Verify project, ref, pipeline source, MR/fork status and default branch from
  coordinator/API metadata. `CI_DEFAULT_BRANCH`, `CI_PROJECT_ID` and other
  variables are not sufficient authorization evidence merely because their
  names look predefined. Keep reusable credentials off the runner.
- The acquired job token can identify its own job through
  [`GET /job`](https://docs.gitlab.com/api/jobs/#retrieve-a-job-by-job-token).
  It is not a general project/pipeline API credential. Confirm the available
  trusted payload fields and endpoint permissions; add a server-side project
  read integration if default-branch/source verification needs it. Never guess
  `main`, accept the workflow's claimed default branch, or widen publication
  when metadata is unavailable.
- Use the recorded job outcome, not the executor process's zero exit code:
  this executor deliberately exits zero after reporting script failure or
  cancellation. Publish only successful default-branch non-MR jobs after the
  same storage fences as GitHub.

## Shared changes and acceptance criteria

Introduce a provider identity resolver behind `CacheVolumes.allocate/1`, retain
pod/node binding, and persist provider/instance/immutable scope plus the verified
publication decision. Migrate existing rows as GitHub identities while retaining
their volume UUIDs; the physical scope derives from UUID and generation, so
existing snapshots need not move. Update the unique index, attribution links,
export documentation and dashboard filters to prevent provider collisions.

Provider adapters should return verified identity and eligibility or an explicit
unavailable result. The existing storage journal, parent retention, reporting,
and generation code should not contain provider-specific API calls.

For each provider, require cold/warm reuse on different hosts, simultaneous
private clones, failed/cancelled jobs, default/non-default branches, fork PR/MR
reads without publication, spoofed variables, missing API metadata, renamed
projects/pipelines, cross-provider/instance ID collisions, clear during a job,
and delayed cleanup. Test Docker mapping separately where advertised. Include
the packaged GitHub action and actual Buildkite plugin/GitLab template in live
smoke runs, rather than testing only the underlying client binary.
