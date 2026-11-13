# Redaction

Redaction rewrites outbound text right before it is sent to the LLM
provider. It runs on user input and tool results. Assistant output and the
system prompt are left untouched: the model has already seen its own prior
responses, and the system prompt is authored by you.

The original messages remain in the session's stored history. Each turn re
runs the redactor on the messages that are about to be sent, so secrets
never leave the BEAM process.

## Default redactor

`Condukt.Redactors.Regex` covers common high precision patterns:

* Emails
* JWTs
* PEM private keys
* Anthropic, OpenAI, GitHub, Google, AWS, Slack tokens

Matches are replaced with `[REDACTED:KIND]` placeholders that the LLM can
still reason about ("an email was here") without learning the value.

```elixir
{:ok, agent} =
  MyApp.CodingAgent.start_link(redactor: Condukt.Redactors.Regex)
```

## Adding patterns

Pass `:extra_patterns` to extend the defaults:

```elixir
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    redactor:
      {Condukt.Redactors.Regex,
       extra_patterns: [{~r/cust_[a-z0-9]+/, "CUSTOMER"}]}
  )
```

Each entry is `{regex, label}`. Matches are replaced with `[REDACTED:LABEL]`.

## Custom redactors

Implement `Condukt.Redactor` to plug in anything you want, including NER
based PII detection or a call to an internal service:

```elixir
defmodule MyApp.Redactor do
  @behaviour Condukt.Redactor

  @impl true
  def redact(text, _opts) do
    MyApp.PiiScanner.scrub(text)
  end
end

MyApp.CodingAgent.start_link(redactor: MyApp.Redactor)
```

`redact/2` receives the raw outbound text and the keyword options that were
passed alongside the module in a `{module, opts}` tuple (or `[]` if none).

## Tool result redaction

Tool results that are not strings (maps, lists) are JSON encoded before the
redactor runs, so secrets embedded in structured output are still caught.
The result the model sees is the redacted JSON.

## Session secrets

Session secrets configured through `:secrets` are converted into a
`Condukt.Redactors.Secrets` redactor and composed ahead of the configured
`:redactor`. This keeps resolved provider secrets in the same outbound
redaction pipeline as regex or custom redactors.

Unlike general outbound redactors, session secret values are also exact-match
redacted from tool results before they are stored in session history. This
prevents resolved session credentials from being persisted if a command prints
them.

## What is not redacted

* The system prompt
* Assistant output
* Project instructions (`AGENTS.md`, `CLAUDE.md`, skills)

Treat the system prompt and project instructions as developer authored
content. If you need redaction there, scrub them before passing them in.
