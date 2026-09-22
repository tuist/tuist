defmodule Atlas.Engineering.Errors.Fingerprint do
  @moduledoc """
  Groups events into issues using a deterministic 64-char hex digest.
  SDK-supplied fingerprints override grouping unless they include a
  `{{ default }}` token, which expands to the event's exception type,
  top in-app frame, and normalized message used by default grouping.

  Log-shaped events carry none of those, so when all of them are blank
  grouping falls back to the identity the event does carry: its
  logger, normalized transaction, level, and tracing event name.
  """

  alias Atlas.Engineering.Errors.SentryEvent

  def compute(%SentryEvent{fingerprint_override: override} = event) when is_list(override) do
    override
    |> Enum.flat_map(fn component ->
      if Regex.match?(~r/\A\{\{\s*default\s*\}\}\z/, component),
        do: default_components(event),
        else: [component]
    end)
    |> Enum.join("|")
    |> hash()
  end

  def compute(%SentryEvent{} = event) do
    event
    |> default_components()
    |> Enum.join("|")
    |> hash()
  end

  defp default_components(event) do
    case exception_components(event) do
      ["", "", "", ""] -> identity_components(event)
      components -> components
    end
  end

  defp exception_components(event) do
    type = event.exception_type || ""

    {function, location} =
      case event.top_frame do
        nil -> {"", ""}
        frame -> {frame["function"] || "", frame["module"] || frame["filename"] || ""}
      end

    message = normalize_text(event.message || event.exception_value || "")

    [type, function, location, message]
  end

  # Without these, every structureless event in a project hashes the
  # same three separators and collapses into one catch-all issue.
  # `transaction` is the one free-text component here, so it gets the
  # same normalization the message does: SDKs that name transactions
  # per record ("GET /users/12345") would otherwise fragment into an
  # issue per record.
  defp identity_components(event) do
    [
      event.logger || "",
      normalize_text(event.transaction || ""),
      event.level || "",
      event.tracing_name || ""
    ]
  end

  defp normalize_text(binary) when is_binary(binary) do
    binary
    |> String.replace(~r/0x[0-9a-fA-F]+/, "0x*")
    |> String.replace(~r/\d+/, "N")
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 200)
    |> String.trim()
  end

  defp normalize_text(_), do: ""

  defp hash(binary) do
    :sha256
    |> :crypto.hash(binary)
    |> Base.encode16(case: :lower)
  end
end
