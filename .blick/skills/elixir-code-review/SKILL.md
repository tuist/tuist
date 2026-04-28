---
name: elixir-code-review
description: Reviews Elixir code for idiomatic patterns, OTP basics, and documentation. Use when reviewing .ex/.exs files, checking pattern matching, GenServer usage, or module documentation.
---

# Elixir Code Review

## Quick Reference

| Issue Type | Reference |
|------------|-----------|
| Naming, formatting, module structure | [references/code-style.md](references/code-style.md) |
| With clauses, guards, destructuring | [references/pattern-matching.md](references/pattern-matching.md) |
| GenServer, Supervisor, Application | [references/otp-basics.md](references/otp-basics.md) |
| @moduledoc, @doc, @spec, doctests | [references/documentation.md](references/documentation.md) |

## Review Checklist

### Code Style
- [ ] Module names are CamelCase, function names are snake_case
- [ ] Pipe chains start with raw data, not function calls
- [ ] Private functions grouped after public functions
- [ ] No unnecessary parentheses in function calls without arguments

### Pattern Matching
- [ ] Functions use pattern matching over conditionals where appropriate
- [ ] `with` has an `else` clause **only when** the error needs transforming or distinguishing (a bare `with` that lets un-tagged error tuples flow through is idiomatic and should not be flagged)
- [ ] Guards used instead of runtime checks where possible
- [ ] Destructuring used in function heads, not body

### OTP Basics
- [ ] GenServers use handle_continue for expensive init work
- [ ] Supervisors use appropriate restart strategies
- [ ] No blocking calls in GenServer callbacks
- [ ] Proper use of call vs cast (sync vs async)

### Documentation
- [ ] Public-API modules (controllers, contexts, public boundaries) have @moduledoc describing purpose
- [ ] Public-API functions have @doc
- [ ] Doctests for pure functions where appropriate
- [ ] No @doc false on genuinely public functions

This repository intentionally does **not** use typespecs. Do **not** flag
missing `@spec`, `@type`, or `@typep` anywhere. Do not flag missing
`@doc`/`@moduledoc` on internal helper modules.

### Security
- [ ] No `String.to_atom/1` on user input (use `to_existing_atom/1`)
- [ ] No `Code.eval_string/1` on untrusted input
- [ ] No `:erlang.binary_to_term/1` without `:safe` option

## Valid Patterns (Do NOT Flag)

- **Empty function clause for pattern match** - `def foo(nil), do: nil` is valid guard
- **Using `|>` with single transformation** - Readability choice, not wrong
- **`@doc false` on callback implementations** - Callbacks documented at behaviour level
- **Any function without `@spec`** - this repo intentionally avoids typespecs
- **Pure formatting / style nits** - `mix format` and `mix credo` cover those in CI
- **Using `Kernel.apply/3`** - Valid for dynamic dispatch with known module/function

## Context-Sensitive Rules

| Issue | Flag ONLY IF |
|-------|--------------|
| Generic rescue | Specific exception types available |
| Nested case/cond | More than 2 levels deep |

## When to Load References

- Reviewing module/function naming → code-style.md
- Reviewing with/case/cond statements → pattern-matching.md
- Reviewing GenServer/Supervisor code → otp-basics.md
- Reviewing @doc/@moduledoc → documentation.md

## Gates — before reporting

Do these **in order** for the review batch. Do not publish findings until each step passes.

1. **Protocol loaded** — Read [review-verification-protocol](../review-verification-protocol/SKILL.md) and apply its checks for each finding category you use (unused, validation, security, performance, etc.). **Pass:** For every substantive finding, you can name which protocol subsection you satisfied or state **N/A** with reason (pure style).
2. **Anchored evidence** — **Pass:** Each finding includes a concrete locator: `path:line` (or line range), or `Module.function/arity` plus a short quoted snippet from the file.
3. **Claims backed by artifacts** — For assertions like unused code, missing validation, or security risk, **Pass:** You attach the supporting artifact (e.g. search results, file read scope) or downgrade the item to an explicit **question** / **uncertain** with what you did not verify.

## Before Submitting Findings

Complete **Gates — before reporting** (section above) first; the verification protocol is mandatory input to those gates.
