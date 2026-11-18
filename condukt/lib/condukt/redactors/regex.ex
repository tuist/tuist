defmodule Condukt.Redactors.Regex do
  @moduledoc """
  Default regex-based redactor for common high-precision secret patterns.

  Matches and replaces:

  - Email addresses (`EMAIL`)
  - PEM private key blocks (`PRIVATE_KEY`)
  - JSON Web Tokens (`JWT`)
  - Anthropic API keys (`ANTHROPIC_KEY`)
  - OpenAI/Stripe-style `sk-` keys (`API_KEY`)
  - GitHub personal/OAuth/server tokens (`GITHUB_TOKEN`)
  - Google API keys (`GOOGLE_API_KEY`)
  - AWS access key IDs (`AWS_ACCESS_KEY`)
  - Slack tokens (`SLACK_TOKEN`)

  Each match is replaced with `[REDACTED:KIND]` so the LLM still receives a
  semantically meaningful placeholder it can reason about.

  Patterns are applied in order; more specific patterns (e.g. `sk-ant-...`)
  run before broader ones (`sk-...`) so the right label wins.

  ## Customising patterns

  Pass `:patterns` as a list of `{Regex.t(), label}` tuples to replace the
  defaults entirely:

      {Condukt.Redactors.Regex, patterns: [{~r/internal-id-\\d+/, "INTERNAL_ID"}]}

  Or pass `:extra_patterns` to append to the defaults:

      {Condukt.Redactors.Regex, extra_patterns: [{~r/cust_[a-z0-9]+/, "CUSTOMER"}]}
  """

  @behaviour Condukt.Redactor

  @default_patterns [
    {~r/-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY(?: BLOCK)?-----[\s\S]*?-----END (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY(?: BLOCK)?-----/,
     "PRIVATE_KEY"},
    {~r/\beyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\b/, "JWT"},
    {~r/\bsk-ant-[A-Za-z0-9_\-]{20,}/, "ANTHROPIC_KEY"},
    {~r/\bsk-[A-Za-z0-9_\-]{20,}/, "API_KEY"},
    {~r/\bgh[oprsu]_[A-Za-z0-9]{30,}/, "GITHUB_TOKEN"},
    {~r/\bxox[abprs]-[A-Za-z0-9\-]{10,}/, "SLACK_TOKEN"},
    {~r/\bAIza[0-9A-Za-z_\-]{35}\b/, "GOOGLE_API_KEY"},
    {~r/\bAKIA[0-9A-Z]{16}\b/, "AWS_ACCESS_KEY"},
    {~r/\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b/, "EMAIL"}
  ]

  @doc """
  Returns the built-in pattern list as a list of `{Regex.t(), label}` tuples.
  Useful when composing with `:extra_patterns`.
  """
  def default_patterns, do: @default_patterns

  @impl Condukt.Redactor
  def redact(text, opts) when is_binary(text) do
    patterns =
      case Keyword.fetch(opts, :patterns) do
        {:ok, patterns} -> patterns
        :error -> @default_patterns ++ Keyword.get(opts, :extra_patterns, [])
      end

    Enum.reduce(patterns, text, fn {regex, label}, acc ->
      Regex.replace(regex, acc, "[REDACTED:#{label}]")
    end)
  end
end
