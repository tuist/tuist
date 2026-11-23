defmodule Atlas.Engineering.Errors.Fingerprint do
  @moduledoc """
  Groups events into issues using a deterministic 64-char hex digest.
  SDK-supplied fingerprints override grouping unless they include a
  `{{ default }}` token, which expands to the event's default grouping
  components.

  Default grouping uses the first exception's type, the top in-app
  frame, and the normalized message, followed by `Type: value` for
  every further exception in the chain. Sentry sends chained
  exceptions oldest first, so `values[0]` is the root cause and the
  rest are the errors that wrapped it; two failures with the same root
  cause but different outer errors are different issues.

  Log-shaped events carry none of those, so when all of them are blank
  grouping falls back to the identity the event does carry: its
  logger, normalized transaction, level, and tracing event name.

  Pulse's `sentry_errors` pipeline (`infra/helm/pulse/sentry-errors.yaml`)
  ports this module; `infra/helm/pulse/sentry-errors-cases.json` pins
  both. Change them together.
  """

  alias Atlas.Engineering.Errors.SentryEvent

  # Applied in this order, so a URL or UUID is replaced whole before its
  # digits could be, and dates, addresses and hex before ints. `\b` is
  # ASCII here (no `u` flag); the pipeline uses `(?-u:\b)` to match.
  @placeholders [
    {~r/[A-Za-z][A-Za-z0-9+.-]*:\/\/[^ \t\n\x0B\x0C\r\x22\x27<>]+/, "<url>"},
    {~r/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/, "<email>"},
    {~r/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/, "<uuid>"},
    {~r/[0-9]{4}-[0-9]{2}-[0-9]{2}(?:[T ][0-9]{2}:[0-9]{2}(?::[0-9]{2}(?:[.,][0-9]+)?)?(?:Z|[+-][0-9]{2}:?[0-9]{2})?)?/,
     "<date>"},
    {~r/[0-9]{1,3}(?:\.[0-9]{1,3}){3}/, "<ip>"},
    {~r/\b[0-9a-f]{40}\b/, "<git_sha>"},
    {~r/0[xX][0-9a-fA-F]+|\b[0-9a-fA-F]{16,}\b/, "<hex>"},
    {~r/[0-9]+\.[0-9]+/, "<float>"},
    {~r/[0-9]+/, "<int>"}
  ]

  def compute(%SentryEvent{} = event), do: compute(event, :current)

  @doc """
  The fingerprint the event had before typed placeholders and exception
  chains (November 2026). `Atlas.Engineering.Errors.IssueCoalescer` uses
  it to carry an issue's status, assignee and first sighting over to the
  issue that the current rules group the same events into.
  """
  def compute_legacy(%SentryEvent{} = event), do: compute(event, :legacy)

  defp compute(%SentryEvent{fingerprint_override: override} = event, rules) when is_list(override) do
    override
    |> Enum.flat_map(fn component ->
      if Regex.match?(~r/\A\{\{\s*default\s*\}\}\z/, component),
        do: default_components(event, rules),
        else: [component]
    end)
    |> Enum.join("|")
    |> hash()
  end

  defp compute(%SentryEvent{} = event, rules) do
    event
    |> default_components(rules)
    |> Enum.join("|")
    |> hash()
  end

  defp default_components(event, rules) do
    case exception_components(event, rules) ++ chain_components(event, rules) do
      ["", "", "", ""] -> identity_components(event, rules)
      components -> components
    end
  end

  defp exception_components(event, rules) do
    type = event.exception_type || ""

    {function, location} =
      case event.top_frame do
        nil -> {"", ""}
        frame -> {frame["function"] || "", frame["module"] || frame["filename"] || ""}
      end

    message = normalize_text(event.message || event.exception_value || "", rules)

    [type, function, location, message]
  end

  defp chain_components(_event, :legacy), do: []

  defp chain_components(%SentryEvent{exception_chain: chain}, :current) do
    Enum.map(chain || [], fn {type, value} -> type <> ": " <> normalize_text(value, :current) end)
  end

  # Without these, every structureless event in a project hashes the
  # same three separators and collapses into one catch-all issue.
  # `transaction` is the one free-text component here, so it gets the
  # same normalization the message does: SDKs that name transactions
  # per record ("GET /users/12345") would otherwise fragment into an
  # issue per record.
  defp identity_components(event, rules) do
    [
      event.logger || "",
      normalize_text(event.transaction || "", rules),
      event.level || "",
      event.tracing_name || ""
    ]
  end

  defp normalize_text(binary, :current) when is_binary(binary) do
    @placeholders
    |> Enum.reduce(binary, fn {pattern, placeholder}, text -> String.replace(text, pattern, placeholder) end)
    |> collapse()
  end

  defp normalize_text(binary, :legacy) when is_binary(binary) do
    binary
    |> String.replace(~r/0x[0-9a-fA-F]+/, "0x*")
    |> String.replace(~r/\d+/, "N")
    |> collapse()
  end

  defp normalize_text(_, _rules), do: ""

  defp collapse(binary) do
    binary
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 200)
    |> String.trim()
  end

  defp hash(binary) do
    :sha256
    |> :crypto.hash(binary)
    |> Base.encode16(case: :lower)
  end
end
