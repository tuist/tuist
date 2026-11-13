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

Release notes don't change which preview a build belongs to. The first notes a preview receives are kept: a later upload can add notes to a preview that has none, but can't overwrite or clear existing ones. Previews uploaded before release notes existed stay valid without them.

Self-hosted deployments need a server version that supports release notes and track filtering, together with an updated client. Older servers ignore the notes. For the track and search filters of the list endpoints, see the [API reference](https://tuist.dev/api/docs).

## Pull/merge request comments {#pullmerge-request-comments}

> [!WARNING]
> **Git forge integration required**
>
> To get automatic pull/merge request comments, integrate your <.localized_link href="/guides/server/accounts-and-projects">remote project</.localized_link> with a Git forge: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link>, or <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.

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
  "url": "https://tuist.dev/preview/1234567890",
  "qrCodeURL": "https://tuist.dev/preview/1234567890/qr-code.svg"
}
```
