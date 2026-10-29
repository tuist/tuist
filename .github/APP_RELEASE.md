# Companion app stable hotfixes

Source preparation is separate from permission to release. Merging, dispatching
App Release, signing/notarizing, GitHub/Sparkle publication, Homebrew updates and
mobile-store promotion require the release owner's separate authorization.

## Establish the source boundary first

- macOS: inspect the live `appcast` release's `appcast.xml` asset and the DMG's
  `app@X.Y.Z` release/tag. Create a release branch at that exact commit and review
  the complete hotfix diff against it. Do not substitute current main.
- iOS: obtain the production App Store version, selected build number and that
  uploaded build's immutable source SHA/run. An approved/closed version string
  does not identify source or demonstrate that a later fix is installed.
- Android: obtain the production track's versionName/versionCode and uploaded
  AAB's immutable source SHA/run. A successful upload to `internal` with status
  `DRAFT` is not a production release. Public listing unavailability does not
  establish either a version or that there are no production users.

GitHub app tags establish the macOS source boundary, not mobile-store contents.
Backport each mobile client only after its store-build-to-source mapping is known.
Do not retrieve credentials or sign into store accounts to fill that gap without
authorization; ask the owner for the mapping/export instead.

## Qualify and release the macOS slice independently

1. Review the candidate's complete diff against the exact stable tag. Merge the
   source PR into `releases/app-X.Y.Z` and the release-support PR into main only
   after separate review/authorization. Workflow-only support changes do not
   trigger the ordinary app release's push path filters.
2. Fetch the stable release branch from origin and select its **final merged
   tip**, not an unmerged PR head or arbitrary descendant such as main. Complete
   native dependency installation, generation, implicit dependency inspection,
   focused shared HTTP/TLS tests, unsigned app build and app tests on that exact
   tip. Run local-wire tests with Homebrew OpenSSL 3; public TLS controls are a
   separate opt-in qualification. Retain exact commands, outputs and source SHA.
   Confirm the lockfile was regenerated, not guessed.
3. After explicit release authorization, select **App Release** on **main** and
   dispatch with `source_sha` equal to that qualified merged tip's full SHA and
   `stable_tag` equal to the current live macOS tag. The planner derives and fetches
   `releases/app-X.Y.Z` from that tag and requires its current tip to match; the
   publisher refetches and repeats the check immediately before publication. If
   the branch moves, stop and qualify its new final tip before replanning.
4. Manual dispatch is **macOS only**. It derives the next patch from the live
   stable tag, pins build/tag/notes to the supplied source, and skips both stores.
   It never infers mobile production versions or promotes a mobile draft. The
   ordinary main push path retains its existing three-platform success gates.
5. Verify the public DMG/checksums, tag source, Sparkle version/build/signature,
   real update installation and Homebrew cask before announcing availability.
   A successful packaging job alone is not a published stable update.

## Recover a partial release without changing its identity

All app releases share one concurrency group because they update one live feed.
Never start a newer release while recovering a partial publication.

- Before GitHub publication: rerun only the failed publisher job in the original
  run while its `app-artifacts` remain available (retained seven days). Keep the
  original successful packaging job, source SHA, version and build intact.
- After GitHub publication: inspect the tag and all assets/checksums before any
  retry. Finish the missing feed/Homebrew step using that run's original signed
  DMG and appcast. Do not rerun packaging, overwrite a published DMG with a new
  build, move a tag or derive replacement artifacts from newer main. If original
  artifacts cannot be recovered, stop and plan a new patch version.
- If another release advanced the live feed, do not overwrite it with an old
  artifact's feed. Reconcile with the release owner using the exact existing
  signed artifact; never generate a rollback feed implicitly.
- A prior main run blocked by an iOS upload is not a stable-source hotfix. Recover
  it only as that original source/version, with separate owner approval; otherwise
  use the qualified stable backport and macOS-only lane.

Credential-free checks:

```bash
python3 .github/scripts/app-hotfix-plan.test.py
node --test .github/scripts/app-release.test.cjs
actionlint -shellcheck= .github/workflows/app-release.yml
```
