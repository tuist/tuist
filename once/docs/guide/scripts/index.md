# Scripts

Scripts are the first way Once makes cacheable actions concrete. Keep the
file, keep the implementation, and add a small contract that tells Once
what the script reads, what it writes, and which host values affect the
result.

## Why Scripts

Most repositories already have a long tail of scripts: test setup, asset
generation, packaging, fixture updates, deployment hooks, local tools, and
CI glue. They are important, but they often sit outside any cacheable
execution model. A developer, CI job, or agent runs them again because
there is no shared contract that says what changed.

Once gives those scripts that contract without asking teams to move the
implementation into a new build-system shape.

::: tip Build systems can model this too
Build systems can model cacheable workflows with rich dependency graphs,
but moving existing repository automation into that shape can be a large
product and migration decision. Once is for the scripts you already have
and want to make cacheable without rewriting them as build rules.
:::

## How It Works

Start with a normal script. Point the shebang at Once, keep the
implementation, and add a few `# once` comments at the top:

```sh
#!/usr/bin/env -S once exec -- bash
# once input "../src/**/*"
# once output "../dist/"
# once env "NODE_ENV"
# once cwd ".."

npm run build
```

Those comments are the script contract:

- **Inputs**: The files, directories, and globs that decide whether the work changed.
- **Outputs**: The files or directories Once should restore on a cache hit.
- **Environment variables**: Declared host values that are forwarded to the script and included in the cache key.
- **Working directory**: The directory where the script should run.

Then run the script directly:

```sh
./scripts/build.sh
```

Once reads the script, hashes the declared contract, and either reuses a
previous result or runs the command and stores stdout, stderr, exit status,
and declared outputs. Workspace-level `once.toml` files are reserved for
shared configuration such as cache provider settings.

## Next

Read [Caching](/guide/scripts/caching) for annotation examples across
languages and [Runtime](/guide/scripts/runtime) for the `once cache` CLI
primitives that scripts can call directly.
