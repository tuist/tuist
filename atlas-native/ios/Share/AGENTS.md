# Moodboard share extension

`AtlasShare` accepts one HTTPS URL and/or plain text through the system share sheet.
It has no networking, OAuth, Rust, Keychain, remote HTML or launch-host workaround.
Local images/videos/files are explicitly rejected; public media links work normally.
The system compose sheet saves a protected, backup-excluded atomic file in App Group
`group.dev.tuist.atlas.share`. Completion explicitly says it is saved **on this device**.

The host publishes only a random recipient nonce and selected server origin after
sign-in. Capture files bind to that exact recipient. Logout removes the recipient
before credentials and purges its inbox; stale extension writers cannot transfer a
capture to a later user. Session restoration retains the Keychain nonce; explicit
new sign-in creates a new one. Never put OAuth tokens or provider credentials here.

Profile's Shared items opens the review inbox (also offered on foreground). Server
suggestions fill untouched fields once, and a failed suggestion never prevents a
manual save. A first save freezes/persists the exact payload and UUID; uncertain
retries cannot edit or generate a new identity. Only confirmed saves remove files.
Inference is explicit in the review disclosure and uses the server's configured
provider; shared content is untrusted input, with no model tools or write authority.

Once builds separate simulator/device `.appex` targets and embeds before host signing.
Distribution needs a separately provisioned Share App ID/profile and the exact App
Group on both profiles. Builds never provision Apple capabilities. Validate real
Safari/text share-sheet discovery, cancellation, offline retry, sign-out and review
on macOS/iOS; Linux cannot establish iOS compilation, installation or UI behavior.
