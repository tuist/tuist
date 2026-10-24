defmodule Atlas.Orbit.Rendering do
  @moduledoc """
  Bounded, display-safe renderings of tool calls.

  Tool cards show participants what the assistant looked up, not raw tool
  payloads. Values under keys that look like credentials or signed links are
  replaced before rendering, and every string is truncated. The model receives
  its own bounded copy of the result; neither copy is written to logs, audit
  events, or agent session telemetry.
  """

  @input_limit 2_000
  @output_limit 4_000
  @model_limit 24_000
  @account_summary_fields ~w(name primary_domain status segment deal_stage legal_name)
  @redacted "[redacted]"
  @sensitive ~r/(token|secret|password|passphrase|api_?key|credential|authorization|cookie|dsn|signature|signed|download_url|upload_url|private_key|license_key|verifier)/i

  def input(arguments) when is_map(arguments), do: arguments |> redact() |> encode() |> truncate(@input_limit)

  def input(_arguments), do: ""

  def output(result, tool_name \\ nil) do
    value = result |> normalize() |> redact()
    rendered = encode(value)

    if tool_name == "get_account" and (String.length(rendered) > @output_limit or byte_size(rendered) > @output_limit) do
      account_summary(value, rendered)
    else
      truncate(rendered, @output_limit)
    end
  end

  # A full account bundle commonly exceeds the evidence budget. Keep a valid,
  # bounded JSON summary so Components can still project the authorized card.
  defp account_summary(%{"account" => %{"name" => name} = account}, _rendered) when is_binary(name) and name != "" do
    summary =
      account
      |> Map.take(@account_summary_fields)
      |> Enum.flat_map(fn
        {key, value} when is_binary(value) -> [{key, account_field(value)}]
        _ -> []
      end)
      |> Map.new()

    encode(%{
      "account" => summary,
      "truncated" => true,
      "notice" => "Additional account context omitted from this summary."
    })
  end

  defp account_summary(_value, rendered), do: truncate(rendered, @output_limit)

  defp account_field(value) do
    value
    |> Stream.unfold(&String.next_codepoint/1)
    |> Enum.take(80)
    |> Enum.join()
  end

  def for_model(result), do: result |> normalize() |> redact() |> encode() |> truncate(@model_limit)

  def error(message) when is_binary(message), do: truncate(message, 500)
  def error(_message), do: "The tool call failed."

  def truncate(text, limit) when is_binary(text) do
    if String.length(text) > limit do
      String.slice(text, 0, limit - 1) <> "…"
    else
      text
    end
  end

  defp normalize(text) when is_binary(text) do
    case JSON.decode(text) do
      {:ok, decoded} when is_map(decoded) or is_list(decoded) -> decoded
      _ -> text
    end
  end

  defp normalize(other), do: other

  def redact(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {key, inner} ->
      key = to_string(key)
      if Regex.match?(@sensitive, key), do: {key, @redacted}, else: {key, redact(inner)}
    end)
  end

  def redact(value) when is_list(value), do: Enum.map(value, &redact/1)
  def redact(value), do: value

  defp encode(text) when is_binary(text), do: text

  # Tool arguments and results reach this point as decoded JSON terms.
  defp encode(value), do: JSON.encode!(value)
end
