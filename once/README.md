<p align="center">
  <img src="assets/header.png" alt="Once: Run once. Reuse everywhere." width="100%" />
</p>

<p align="center">
  <a href="https://github.com/tuist/tuist/actions/workflows/once.yml"><img src="https://github.com/tuist/tuist/actions/workflows/once.yml/badge.svg" alt="CI" /></a>
  <a href="https://github.com/tuist/tuist/releases?q=once%40&expanded=true"><img src="https://img.shields.io/github/v/release/tuist/tuist?filter=once%40*&display_name=tag&sort=semver&label=release" alt="Latest release" /></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-blue" /></a>
</p>

# Once

Once makes project scripts cacheable, observable, and remotely executable. Declare the inputs, outputs, environment, and runtime contract once, then reuse the result locally, in CI, or on a compute provider.

## Quick Start

Describe a script with `# once` annotations:

```sh
#!/usr/bin/env bash
# once input "../assets/**/*"
# once output "../dist/"
# once cwd ".."

npm run build-assets
```

Run it through the cache:

```sh
once exec -- bash scripts/build-assets.sh
once exec --remote --compute microsandbox -- bash scripts/build-assets.sh
```

Scripts can also run directly with a Once shebang:

```sh
#!/usr/bin/env -S once exec -- bash
```

## Documentation

Read the documentation at [once.tuist.dev](https://once.tuist.dev).

## License

[MIT](LICENSE).
