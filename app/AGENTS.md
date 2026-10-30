# iOS and macOS companion app

SwiftUI app with a macOS menu bar and iOS project/preview management. Shared CLI
modules supply server access, domain models, and automation; keep those concerns
in the CLI modules rather than reimplementing them here.

Run from `app/`:

```bash
tuist generate --no-open
xcodebuild build -workspace TuistApp.xcworkspace -scheme TuistApp
xcodebuild test -workspace TuistApp.xcworkspace -scheme TuistApp
```

- iOS preview tests use the `TuistPreviews` scheme with an iOS Simulator destination (`Tests/TuistPreviewsTests`).
- Use SwiftUI for new UI components and follow CLI Swift conventions.
- Only add one-line comments when they explain something non-obvious.
- `TUIST_ENV` selects `development` (local server), `staging`, or `canary`;
  the default is production.

## Release and assets

- `.github/workflows/app-release.yml` triggers on app, app-task, and linked CLI-module changes, not workflow/runner-image changes alone. Cold compilation caches make `--no-binary-cache` archives slow; retain the 50-minute job allowance.
- Build DMGs with `dmgbuild` and `app/dmg-settings.py`, never Finder automation or TCC workarounds: fleet VMs have no responding Finder. Generate appcasts from `app/build/appcast-input`, not the upload artifacts directory, because `generate_appcast` mutates its input.
- `CFBundleVersion` uses epoch seconds and must exceed the newest `sparkle:version` in `app/appcast.xml`; workflow run numbers can reset and cause the DMG to be treated as an old update.
- `AppIcon.icon` requires Xcode 26+ and explicit `glass` values on every layer (omission means true). Inspect at about 95pt, not just 1024px. Regenerate the flat `TuistIcon`/`TuistRoundedIcon` assets from the compiled icon when it changes; monochrome menu/sign-in marks are rasterized at 16pt/20pt.
- Keep the DMG background opaque/light: Finder draws black labels over pictures. The HiDPI TIFF contains 660×400 and 1320×800 representations; icon coordinates match its arrow and `dmg-settings.py`.

## Authentication

- Both login screens keep hosted sign-in buttons and a separate self-hosted HTTPS URL prompt. Hosted sign-in clears saved selection; closing the prompt leaves the screen unchanged, and a saved URL only prefills it.
- Persist URL and client ID together in `AppServerConfigurationKey`, then bind them to `AuthenticationState.loggedIn(account:server:)`. Resolve signed-in requests and credential cleanup with `AppServerEnvironmentService`, not the CLI service. Sign-out retains the prompt selection.
- Self-hosted login reads same-origin `registration_endpoint` from `/.well-known/oauth-authorization-server` and registers a public PKCE client with `tuist://oauth-callback`. Servers without dynamic registration show an update error, never use the hosted client ID. Preserve issuing client IDs during token rotation; never bypass certificate checks or add broad ATS exceptions.
- Use shared `TuistLogging` for persistent application logs and support exports.

## Preview browsing

- macOS discovery covers every branch and result page, never `latest`. Launch by matching bundle ID. Search distinct compatible apps first and fall back to history only for older post-selection platform filtering; reject repeated/empty nonterminal pages instead of capping results.
- Preserve optional tracks/release notes on older `ServerPreview` responses. On iOS, native server-side search covers display names and full notes, combines with whole-track filtering before pagination, and resets on project changes. Debounce and suppress superseded results and errors, including track discovery and project-list fallback.
- Obtain complete project names/counts from authorized `/previews/tracks`, never a downloaded page. Counts stay full-project totals across filters; All includes untracked previews. Older servers remain browsable without invented partial choices/counts. Accept case-only track differences (`citext`), but detect missing/different filters.
- Keep horizontally scrolling Tracks pills below the rounded selector, selected purple; All resets without a separate clear/menu/alert. Release notes are plain text: first nonblank line truncated in rows, full text in details, never Markdown/HTML. Keep the track tag beside the commit hash.
- Empty states use native pull-to-refresh, not a duplicate button; filtered states explain adjusting filters and unfiltered states explain pulling down. Await refresh so its indicator tracks the request; refresh projects when none are loaded.
