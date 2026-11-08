# Project Instructions

When `:load_project_instructions` is enabled (the default), Condukt
inspects the project root configured by `:cwd` at startup and appends local
guidance to the effective system prompt. This is how an agent picks up
project specific conventions without you hard coding them.

## What gets loaded

* `AGENTS.md` at the project root
* `CLAUDE.md` at the project root
* `.agents/skills/*/SKILL.md` for each local skill

Discovered skills are listed in the prompt with their file paths so the
agent can read the full `SKILL.md` instructions when it needs them. The
files themselves are not pre loaded into context: the agent decides when
to use a skill and reads it on demand.

## Enabling and disabling

Project instructions are loaded by default when `cwd` is set:

```elixir
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    cwd: "/path/to/project",
    system_prompt: "You are a helpful coding assistant."
  )
```

Disable for fully static prompts:

```elixir
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    load_project_instructions: false
  )
```

## Authoring `AGENTS.md` and `CLAUDE.md`

Both files use plain Markdown. Use them for things like:

* Conventions ("Prefer `MuonTrap` over `System.cmd/3`.")
* Procedures ("After every change, create a git commit and push it.")
* Domain glossary
* Pointers to important modules

Keep them short. They are prepended to every prompt, so they cost tokens on
every turn.

## Authoring skills

A skill is a directory with a `SKILL.md` file. The convention is one skill
per folder under `.agents/skills/`:

```
.agents/skills/
  release/
    SKILL.md
  changelog/
    SKILL.md
    template.md
```

Each `SKILL.md` should describe:

* What the skill does
* When to use it
* The exact steps the agent should follow
* Any helper files it can read from the same folder

Skills are powerful because they keep specialised playbooks out of the main
system prompt. Only the path and a one line description live in context;
the agent loads the full skill when it needs it.
