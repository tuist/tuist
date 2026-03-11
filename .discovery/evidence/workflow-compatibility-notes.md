# Evidence: workflow compatibility notes

## Current repo assumptions

### Xcode version

From `.xcode-version`:

```text
26.2
```

### CLI workflow

From `.github/workflows/cli.yml`:

```text
runs-on: macos-26
sudo xcode-select -switch /Applications/Xcode_$(cat .xcode-version).app
uses: jdx/mise-action
run: tuist auth login
run: tuist setup cache
run: tuist install
```

### App workflow

From `.github/workflows/app.yml`:

```text
runs-on: macos-26
sudo xcode-select -switch /Applications/Xcode_$(cat .xcode-version).app
uses: jdx/mise-action
run: tuist auth login
run: tuist setup cache
run: tuist install
```

## What this means for the self-hosted Mac

- The host must either provide `/Applications/Xcode_26.2.app` or the workflows must change.
- The host must either make `sudo xcode-select` unnecessary or provide a safe non-interactive path.
- The host does not strictly need `mise` and `tuist` preinstalled because current workflows already use `jdx/mise-action`.
- The host needs simulator readiness before app tests can run.
- The host needs a decision on whether self-hosted jobs keep the current `xcode-select` model or move to `DEVELOPER_DIR`.

## Minimum compatibility checklist

- correct Xcode version installed
- correct Xcode app path available
- default developer dir already selected at bootstrap time
- `mise` installed
- `tuist` installed
- simulator runtimes installed
- cache connectivity over Private Network verified

## Experimental self-hosted workflow path

The repo now includes:

- `.github/workflows/cli-self-hosted.yml`
- `./.github/actions/select-xcode`

Purpose:

- provide one low-risk manual path to exercise the self-hosted Mac runner labels
- support self-hosted runners that already export `DEVELOPER_DIR`
- avoid baking `sudo xcode-select` in every future self-hosted job path

## Xcode path compatibility note

Manual `xcodes` installation on the test host produced:

```text
/Applications/Xcode-26.2.0.app
```

The custom `./.github/actions/select-xcode` action was updated to support both:

- `/Applications/Xcode_26.2.app`
- `/Applications/Xcode-26.2.0.app`
