# Tuist openness

Tuist builds in the open: public source, a public handbook, a public forum, and a documented API. This guide explains what that means in practice, including licensing.

## What is public

- [Source repository](https://github.com/tuist/tuist): the CLI, server, apps, Gradle plugin, Kura cache nodes, and other components. Related open-source projects include XcodeProj and XcodeGraph.
- [Company handbook](https://handbook.tuist.dev): how the company works and decides.
- [Community forum](https://community.tuist.dev): discussion with users and maintainers.
- [API documentation](/api/docs) and [OpenAPI specification](/api/spec): the REST API contract. Requests still require authorization.
- [Openness statement](/marketing-markdown/source/openness): the company's full published perspective.

## Public source is not one license

Components are licensed differently. Check the `LICENSE.md` in each directory before reusing code:

- The CLI and most of the repository: MIT.
- The server (`server/`): Fair Core License with MIT future license (FCL-1.0-MIT). It permits uses such as internal use, education, and research, but not offering a competing commercial product or service; each version becomes MIT two years after release.
- Kura (`kura/`): GNU AGPL v3.

Running a self-hosted Tuist server also requires a paid Enterprise license, per the [self-hosting guide](/en/docs-markdown/guides/server/self-host/server). Trademarks are not licensed with the code; see [Brand](/marketing-markdown/brand).

## Limitations

Openness does not mean every hosted capability is free, every internal endpoint is a supported API, or every component can be deployed or redistributed under the same terms. Not all of Tuist's work is open source. Read the component license, [pricing](/marketing-markdown/pricing), and the [longevity commitment](/marketing-markdown/longevity) when assessing dependency risk.
