# Caching

Script files are the easiest way to make existing repository automation
cacheable through Once without rewriting the implementation.

Most repositories already have a layer of shell, Node, Python, Ruby, or
Elixir automation that does real work but lives outside the native build
graph. Once lets those scripts stay where they are. The script file
remains the source of truth, and Once learns just enough about it to
cache it, inspect it, and schedule it safely.

## Annotated Script Files

Use a script file when the implementation belongs in a real script.
The annotation model works across common scripting languages. For
example:

::: code-group
```sh [Bash]
#!/usr/bin/env bash
# once input "../src/**/*.ts"
# once output "../dist/"
# once env "NODE_ENV"

npm run build
```

```python [Python]
#!/usr/bin/env python3
# once input "../src/**/*.py"
# once output "../dist/"
# once env "PYTHONPATH"

print("build")
```

```ruby [Ruby]
#!/usr/bin/env ruby
# once input "../lib/**/*.rb"
# once output "../dist/"
# once env "RUBYLIB"

puts "build"
```

```elixir [Elixir]
#!/usr/bin/env elixir
# once input "../lib/**/*.ex"
# once output "../dist/"
# once env "MIX_ENV"

IO.puts("build")
```
:::

Ruby, Python, and Elixir all use `#` comments, so the annotations read
naturally in those files. Once also accepts other line-comment forms
such as `//`, `;`, `--`, `%`, and `'` for languages that use them.

## Running Through Once

To run an annotated script file through Once, use the runtime you
would normally use locally and put it after `once exec --`:

```sh
once exec -- bash scripts/build.sh
```

If the file carries `once` headers, Once automatically switches to
script-aware execution. The explicit `--script` form still works when
you want to force that mode.

## Executable Once Shebangs

If you want the file itself to execute through Once, use a Once
shebang and name the runtime there:

::: code-group
```sh [Bash]
#!/usr/bin/env -S once exec -- bash
# once input "../src/**/*.ts"
# once output "../dist/"
# once env "NODE_ENV"

npm run build
```

```python [Python]
#!/usr/bin/env -S once exec -- python3
# once input "../src/**/*.py"
# once output "../dist/"
# once env "PYTHONPATH"

print("build")
```

```ruby [Ruby]
#!/usr/bin/env -S once exec -- ruby
# once input "../lib/**/*.rb"
# once output "../dist/"
# once env "RUBYLIB"

puts "build"
```

```elixir [Elixir]
#!/usr/bin/env -S once exec -- elixir
# once input "../lib/**/*.ex"
# once output "../dist/"
# once env "MIX_ENV"

IO.puts("build")
```
:::

This keeps the script directly executable while still letting Once
apply the annotated cache contract.

The `once` directives at the top of the file describe the parts
Once must reason about: tracked inputs, declared outputs, forwarded
environment variables, and a working directory. That keeps the
implementation and the cache contract in one place.

## Mise File Tasks

Once works beautifully with [Mise file tasks](https://mise.jdx.dev/tasks/file-tasks.html).
Keep the task as an executable script in `mise-tasks/`, `.mise/tasks/`,
or another Mise task directory, add `# once` headers next to the
existing task body, and run it through the same script file:

```sh
# mise-tasks/build
#!/usr/bin/env -S once exec -- bash
#MISE description="Build assets"
# once input "../src/**/*.ts"
# once output "../dist/"
# once env "NODE_ENV"

npm run build
```

Run it the same way you run the rest of your Mise tasks:

```sh
mise run build
```

## Supported Annotations

| Annotation | Purpose |
| --- | --- |
| `input` | Declares tracked files, directories, or globs. |
| `output` | Declares output files or directories that Once should restore on cache hits. |
| `output-symlinks` | Controls output symlink capture. Use `materialize-external` to copy targets outside the output directory, or `preserve` to store links as links. |
| `env` | Forwards selected environment variables from the host and includes them in the cache key. |
| `cwd` | Chooses the working directory for the script. |

Directory outputs default to `materialize-external`, so package-manager
stores linked from outputs such as `node_modules/` can restore from the
cache without depending on the original global store path.

The script file itself is always part of the cache key, even when no
`input` directives are present.

::: tip Path Resolution
`once` paths are resolved relative to the script file's directory,
so the contract stays portable when it lives in `scripts/`, `tools/`,
or any other subdirectory next to the code it automates.
:::
