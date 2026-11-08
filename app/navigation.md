# Web and mobile navigation URLs

The server, iOS, and Android share canonical web addresses for destinations they
all implement. Routes contain identifiers, not serialized API models, credentials,
or commands. Opening a link only navigates; installing,
deleting, signing in, and switching servers still require the existing UI and
authorization. This contract covers the current mobile screens and the Rust
desktop shell. The Swift macOS app does not yet use this navigation contract.

## Route contract

| Destination | URL |
| --- | --- |
| Preview detail | `{serverBaseURL}/{account}/{project}/previews/{previewId}` |
| Native Previews root | `tuist://app/previews` |
| Native Profile | `tuist://app/profile` |

Percent-encode each path segment and the server query value separately. Preview
IDs are opaque single segments. Do not assume UUIDs or interpolate unescaped
handles. HTTPS is canonical; configured local development servers can use HTTP.
The origin identifies the server, including its port and any self-hosted base
path. Default ports, host casing, and trailing base slashes are normalized.

The custom alias
`tuist://app/{account}/{project}/previews/{previewId}?server={serverBaseURL}`
is reserved for explicit native handoff, not sharing. Handoff generators always
include the server. Omitting it still means `https://tuist.dev`, never the current
device environment. Existing aliases remain accepted.

Examples for an agent to include in a jam:

```markdown
[Open your profile](tuist://app/profile)
[Browse previews](tuist://app/previews)
[Open this preview](https://tuist.dev/tuist/ios-app/previews/build-42)
```

Share canonical HTTPS links from agents, notifications, QR codes, and native
Share actions. They work as ordinary browser links without the app installed.
Native-only screens still require an installed app and a jam client that
allows `tuist:` links. Custom schemes have no website fallback and can be claimed
by other apps. This substrate does not change any jam renderer.

Canonical preview links navigate natively when delivered to the app and scoped
to the active server. iOS declares associated domains and the server's Apple
association file grants preview details but excludes `latest` and child routes
such as downloads, icons, and manifests. Android declares narrow
preview intent filters for production, staging, and canary; the server already
serves its package/signing-certificate association. OS verification, the installed
app's signing identity, and the user's link-opening preferences still govern
whether an HTTPS tap opens the app. Arbitrary self-hosted domains are not verified
automatically; explicit custom handoff works there. Profile and the global native
Previews root have no equivalent web routes. The web project's
`/{account}/{project}/previews` list is not the global native tab, and `/previews`
is the marketing page. Those pages, settings, and preview downloads remain web-only.

## Choosing a presentation

- Normal HTTPS taps follow the OS association and user's link-opening preferences.
  Browser same-site navigation does not reliably trigger a native handoff.
- Mobile browsers show an explicit **Open in app** action on preview details. It
  uses the custom alias and only navigates; it does not run or install the preview.
  The existing Download and Run actions keep their separate meanings.
- Native preview details provide **Open on web** using `SFSafariViewController`
  on iOS and Chrome Custom Tabs on Android. This deliberately avoids handing the
  HTTPS URL back to the app. Browser and native sessions authenticate independently;
  no tokens are copied into links or transferred between them.
- Unsupported same-server web URLs delivered by a cached/overbroad OS association
  open in that browser presentation without replacing the native destination.
  Wrong-server links and malformed custom aliases still report an error.

## Delivery and navigation

- Receive links at the app boundary, including cold launches and warm deliveries.
  The latest pending navigation link waits for a signed-in session. OAuth callbacks
  stay on the authentication path and do not overwrite that link.
- Validate the entire route before native navigation. Reject unsupported destinations,
  extra/empty path segments, traversal segments, decoded separators, whitespace,
  control characters, credentials, fragments, and unknown/duplicate parameters.
- Preview links must match the signed-in server's full base URL. Never select a
  server or send credentials to a URL supplied by a navigation link. An invalid or
  wrong-server link reports an error without replacing the current destination.
- A preview deep link selects Previews and replaces its detail path. Back returns
  to the previews list. Repeated deliveries do not accumulate duplicate details.
- Profile selects the Profile tab. Previews-root links clear its detail stack.
  Ordinary platform tab switching retains native behavior.
- On iOS and Android, long-press Profile to switch saved logins, not organizations.
  Rows show the personal account identity and server. Previews keeps all authorized personal
  and organization projects in its existing picker; Jams defaults to the
  signed-in personal account. Preview links are scoped to the server, not a
  previously selected organization. Switching profiles clears open screens,
  drafts, and pending links from the outgoing session.
- These are navigation addresses, not authorization grants. The existing detail
  requests still enforce access and report missing or inaccessible previews.

## Calling from app code

On iOS, `TuistNavigation.AppRoute.url(serverURL:)` generates canonical URLs and
`handoffURL(serverURL:)` generates explicit native aliases. The root owns an
observable `AppNavigation`, injected through SwiftUI's environment. Features call
`navigation.navigate(to:)`; Previews binds its `NavigationStack` to the same typed
path that external links update. SwiftUI `Link`/`openURL` calls using supported
canonical URLs or `tuist://app` are intercepted in-process instead of relaunching
the app. Other links continue
to the system. New destinations belong in `AppRoute` and the root/feature mapping,
not another `onOpenURL` handler.

On Android, `AppRoute.parse`/`toUrl` define the canonical wire format, with
`toHandoffUrl` for explicit native aliases.
`AppNavigationViewModel` owns pending delivery in `SavedStateHandle`, preserving
unconsumed links across activity recreation without replaying consumed launch
intents. `HomeScreen` maps routes onto the existing type-safe Compose destinations.
Feature callbacks and tab actions use that same entry point. Add destinations to
the parser, generator, and native mapping together.

The Rust desktop app uses `tuist-navigation::Route` for the same wire format and
`Navigation` for pending delivery and tab/detail state. Command-line URL arguments,
gpui URL events, and authenticated local forwarding from a second launch all
reach the root before the signed-in workspace. OAuth remains on its loopback
callback, separate from navigation. Linux and Windows require explicit protocol
registration; see `desktop/README.md`. They do not claim all HTTPS links.

Desktop preview browsing is not implemented yet. A preview link opens a handoff
screen with the identifiers, **Copy link**, **Open on web**, and Back, not fetched
preview metadata or a Run/Install action. Canonical web links continue to work in
the system browser. Never imply this screen has checked preview access.

`app/Fixtures/Navigation/routes.json` is the shared executable contract: canonical
web URLs, native aliases, encoded identifiers, server base paths, and web-only
destinations. Swift and Kotlin tests validate generation, parsing, and browser
fallback; server tests verify the same canonical paths against its real router.
Extend these fixtures and all native mappings together, without requiring a
runtime routing service or coupling native stacks to Phoenix implementation details.

Run the route-contract and delivery tests whenever extending this vocabulary:

```sh
# From app/, after tuist install and tuist generate --no-open
xcodebuild test -workspace TuistApp.xcworkspace -scheme TuistNavigation -destination 'platform=macOS'

# From android/
./gradlew testDebugUnitTest assembleDebug

# From server/
mix test test/tuist_web/controllers/well_known_controller_test.exs test/tuist_web/live/preview_live_test.exs
```

Smoke-test an installed simulator/emulator build without embedding credentials:

```sh
xcrun simctl openurl <simulator-id> 'tuist://app/profile'
adb shell am start -W -a android.intent.action.VIEW -d 'tuist://app/profile' dev.tuist.app
```

Check signed-out delivery followed by sign-in, repeated delivery, another link
while already on a detail, Back, wrong-server rejection, and OAuth sign-in with a
pending destination. Android additionally needs activity recreation coverage.

## Platform research and rationale

- Apple recommends data-driven navigation when the app needs to control or
  restore a stack. A homogeneous route array is sufficient here; a type-erased
  `NavigationPath` and multiple feature-local URL handlers are unnecessary.
  [Understanding the navigation stack](https://developer.apple.com/documentation/swiftui/understanding-the-navigation-stack)
- SwiftUI delivers both custom URLs and Universal Links through `onOpenURL`.
  Handle them above bootstrap/authentication so a feature need not already exist.
  [onOpenURL](https://developer.apple.com/documentation/swiftui/view/onopenurl(perform:))
- Android recommends type-safe Compose destinations, passing only identifiers,
  and decoupling screens from `NavController` through callbacks. Keep the current
  Compose graph rather than replacing it with a URL-only navigation framework.
  A central ingress validates server scope and gates on authentication before
  reaching that graph, rather than allowing an implicit destination to bypass it.
  [Navigation with Compose](https://developer.android.com/develop/ui/compose/navigation)
- Both platforms prefer verified web links for public sharing. Those require
  two-way website/app association, unlike custom schemes. Reuse the existing
  verified preview addresses, and reserve the custom `app` authority for native
  navigation, separate from `tuist://oauth-callback` and CLI URL consumers.
  [Apple Universal Links](https://developer.apple.com/ios/universal-links)
  · [Android App Links](https://developer.android.com/training/app-links)

Future destinations should be additive. Before publishing new HTTPS app routes,
provide their web fallback and update the Apple association paths and Android
intent filters together. Do not redirect or capture all website URLs merely to
make native navigation more convenient.
