## Tracks with tuist share {#share-tracks}

For workflows that publish with `tuist share`, use `--track` to select a track:

```bash
tuist share App --track beta
tuist share App --track nightly
```

## Release notes {#release-notes}

Use tracks for environment groups and release notes for the purpose of an individual build:

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

Replace `App` with your app name, application file path, or executable distribution and its `--executable` option. Release notes are optional plain text, up to 10,000 characters. The first nonblank line appears as a single-line snippet in preview lists, so build numbers and other identifying information are visible at a glance. Long lines are truncated; full notes appear on the detail pages. Search matches display names and full release notes, including lines not shown in the snippet. Multiline notes are supported, for example `--release-notes "$(< release-notes.txt)"`. They do not change the app's display name or its track.

### Compatibility {#preview-metadata-compatibility}

Release notes are additive metadata, not part of a preview's identity. Uploads from old and new clients still group into the same preview across platforms. The first nonblank notes are retained: a later upload can fill notes that were previously absent, but cannot overwrite existing notes. Omitting `release_notes`, sending `null`, or sending an empty or whitespace-only string never clears notes. Existing previews are not backfilled and remain valid without notes.

The list API's optional `track` query parameter matches a whole track name, case-insensitively, consistent with existing track storage. Omit it or send an empty value (`?track=`) to list all tracks. Track names remain open strings, not a fixed list of values. `GET /api/projects/:account_handle/:project_handle/previews/tracks` returns `{total_count, tracks: [{name, count}]}` with sorted, case-insensitively grouped named tracks, under the same preview-read authorization as listing builds. Counts cover the whole project independently of pagination, search, and the selected track; the total includes untracked previews. Only listable previews with a bundle identifier are counted. The list API also accepts optional `search` for a literal, case-insensitive substring of the display name or full release notes, combined with the track before pagination. Existing `display_name` filtering remains exact.

Old clients can continue uploading and listing previews without sending either field. New clients accept older responses that omit track or notes, and ignore unknown response properties added by future servers. API integrations should likewise ignore unknown response properties so additive metadata remains compatible.

Self-hosted deployments need a server version that supports release notes and track filtering, together with an updated client, to use these features. Older servers may ignore notes or unknown query parameters.

## Pull/merge request comments {#pullmerge-request-comments}

> [!WARNING]
> **Integration With Git Platform Required**
>
> To get automatic pull/merge request comments, integrate your <.localized_link href="/guides/server/accounts-and-projects">remote project</.localized_link> with a <.localized_link href="/guides/server/authentication">Git platform</.localized_link>.

Once your Tuist project is connected with your Git platform, add <.localized_link href="/cli/share">`tuist share`</.localized_link> after a successful application build in CI. Tuist will post a preview link directly in your pull/merge requests, so reviewers can test without building locally:

![GitHub app comment with a Tuist Preview link](/images/guides/features/github-app-with-preview.png)

## Automations {#automations}

Use `--json` to get JSON output from `tuist share`:

```bash
tuist share --json
```

Use the result for custom automations, such as posting a Slack message from CI. The `url` key contains the full preview link; `qrCodeURL` points to a QR code image for opening the preview on a device:

```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
