# Cache CLI

Most repositories have a long tail of scripts that exist next to the
build: test runners, codegen, dependency installs, environment
bootstraps. They are usually invisible to caching because they live
outside the formal graph, and so they run from scratch every time, on
every machine, even when their inputs have not changed.

The cost of that adds up quickly. A test suite that takes ninety
seconds runs ten times a day during a refactor. `npm install` re-runs
on every CI job, even when the lockfile is identical. An agent
operating across ten parallel worktrees redoes the same codegen step
ten times because none of the workers know the others already paid
for it.

The `once cache` CLI exposes Once's content-addressed store
directly to those scripts so they can stop. Declare the inputs that
determine a result, ask the cache whether you have already produced
that result, and either skip the work or restore the artifact. The
script stays a script. The speedup comes from the same store that Once
uses for declared script actions.

The surface is small. Two caches, mirroring the shape that Bazel and
the [Remote Execution API](https://github.com/bazelbuild/remote-apis)
settled on: a content-addressed store of bytes, plus a map from an
action's input digest to the result that input produced.

## Inputs

The action cache identifies a record by hashing the inputs you
declare. The grammar:

| Spec | Meaning |
| --- | --- |
| `<path>` | A file or directory on disk. Directories are walked sorted (content + relative path per entry), so the digest is deterministic. |
| `path:<path>` | Explicit path form, for paths whose names contain `:`. |
| `value:<str>` | A literal string. |
| `env:<NAME>` | Environment variable `<NAME>`, hashed as `<NAME>\0<value>` so two variables sharing a value do not collide. Unset variables hash as empty. |
| `-` | Standard input. May appear at most once across all inputs. |

Inputs are hashed in declaration order and combined. The order matters:
`(a, b)` and `(b, a)` produce different digests.

## Blob cache

The blob cache stores bytes and returns them by their content hash. A
`get <digest>` always returns bytes that hash back to the digest you
asked for; this invariant is what makes restoring outputs from a
cached action result safe.

| Command | Purpose |
| --- | --- |
| `once cache blob put [<path>]` | Store bytes from a file (or stdin) and print their BLAKE3 digest. |
| `once cache blob get <digest>` | Fetch bytes by digest. |
| `once cache blob exists <digest>` | Exit 0 on hit, 1 on miss. With `--format json`/`toon`, always exit 0 and emit `{"digest":"...","present":true|false}`. |

This namespace travels through whatever remote infrastructure your
`once.toml` configures (for example, [Tuist](https://tuist.dev)).
`get` falls back to the remote on local miss; `exists` consults the
remote too, so the two are symmetric.

## Action cache

Maps an action digest to an `ActionResult`: the captured exit code,
optional stdout and stderr digests, and any declared outputs as
`path -> blob digest`. This is the primitive both for remembering
whether a *run* succeeded and for memoising an *artifact* a script
produced from a set of inputs, since each declared output points back
into the blob cache by content hash.

Both `get` and `put` identify the action by an input declaration
(`--input ...`). Declare the same inputs on the read and the write so
the two derive the same key. A pre-computed digest may also be passed
positionally when you already have one in hand (for example, from a
prior `cache action get --format json`).

| Command | Purpose |
| --- | --- |
| `once cache action get --input <spec> ...` | Look up a result by declared inputs. Always exits 0; parse `--format json` for `"hit": true\|false` and `"result"`. |
| `once cache action get ... --if-success` | Exit 0 only when there is a hit AND the recorded exit code is 0. Exits non-zero on miss or on a cached failure. |
| `once cache action put --input <spec> ... [--exit-code N] [--stdout <d>] [--stderr <d>] [--output path=digest ...]` | Record a result under the declared inputs. `--exit-code` defaults to 0. |
| `once cache action forget <digest>` | Drop a cached action result by digest. |

## Inspecting

| Command | Purpose |
| --- | --- |
| `once cache stats` | Print counts and on-disk size for the blob cache and the action cache. |

## Examples

### Skip a test run when inputs have not changed

```sh
#!/usr/bin/env bash
set -euo pipefail

inputs=(
  --input src
  --input test
  --input vitest.config.ts
  --input pnpm-lock.yaml
)

if once cache action get "${inputs[@]}" --if-success; then
  echo "vitest: cached green run for these inputs, skipping."
  exit 0
fi

pnpm vitest run

# `put` records exit_code 0 by default, so the same inputs short-circuit
# on the next invocation. A failed run is not recorded - `set -e` would
# have exited above, so we only reach this line on success.
once cache action put "${inputs[@]}"
```

The same shape works for any test runner, linter, type checker, or
codegen step whose result is a deterministic function of a set of
files.

### Restore an artifact instead of regenerating it

When what you want to remember is the *output* of a step (a tarball,
a generated folder, a built binary), put the artifact in the blob
cache and reference it from an action result keyed by the inputs that
produced it. The next run computes the same action digest, fetches the
result, and pulls the artifact straight from the blob cache.
`npm install` is the canonical example.

```sh
#!/usr/bin/env bash
set -euo pipefail

inputs=(--input package.json --input package-lock.json)

# If we recorded a result for these inputs, restore the tarball.
result=$(once cache action get "${inputs[@]}" --format json)
if echo "$result" | grep -q '"hit":true'; then
  digest=$(echo "$result" | jq -r '.result.outputs["node_modules.tar"]')
  once cache blob get "$digest" | tar -xf -
  echo "node_modules: restored from cache."
  exit 0
fi

# Cache miss: install, store the tarball in the blob cache, and
# record an action result pointing at it.
npm install
nm_digest=$(tar -cf - node_modules | once cache blob put)
once cache action put "${inputs[@]}" \
  --output node_modules.tar="$nm_digest"
```

Three operations carry the whole flow: probe the action cache, put
the tarball in the blob cache, record the result. The blob cache
deduplicates: two teammates whose installs produce byte-identical
tarballs end up sharing one entry.

The same pattern works for `pip install`, `bundle install`,
`cargo fetch`, or any output a tool produces deterministically from a
small set of input files.

### Restore a mise-managed toolchain

[mise-action](https://github.com/jdx/mise-action) caches
`~/.local/share/mise/` between GitHub Actions runs so the second job
that asks for `node 20.x` and `python 3.13` does not re-download them.
The cache key is `(prefix, runner platform, mise version, mise config
+ lockfile, install args, MISE_ENV)`; the cached payload is the whole
mise data directory. Nothing about that shape is GitHub-specific, and
the same script gives a single dev machine, an agent's worktree, and
a CI runner the same speedup.

```sh
#!/usr/bin/env bash
set -euo pipefail

# The platform discriminator matters: a mise tree built on macOS arm64
# cannot run on Linux x86_64. We feed both env vars in so switching
# machines moves the cache key. `value:` carries a prefix you bump when
# the cache format itself changes.
inputs=(
  --input value:mise-v1
  --input env:OSTYPE
  --input env:HOSTTYPE
  --input mise.toml
  --input mise.lock
)

mise_dir="${MISE_DATA_DIR:-$HOME/.local/share/mise}"

result=$(once cache action get "${inputs[@]}" --format json)
if echo "$result" | grep -q '"hit":true'; then
  digest=$(echo "$result" | jq -r '.result.outputs["mise.tar"]')
  mkdir -p "$mise_dir"
  once cache blob get "$digest" | tar -xzf - -C "$(dirname "$mise_dir")"
  echo "mise: restored toolchain from cache."
else
  mise install --locked
  tools_digest=$(
    tar --sort=name -czf - -C "$(dirname "$mise_dir")" "$(basename "$mise_dir")" \
      | once cache blob put
  )
  once cache action put "${inputs[@]}" --output mise.tar="$tools_digest"
fi
```

The local-development payoff is the part mise-action cannot deliver: a
team member who already installed the same toolchain on their machine
has primed your cache; switching to a new branch with a different
`mise.toml` restores its toolchain in the time it takes to extract a
tarball, and switching back restores the previous one for free.
