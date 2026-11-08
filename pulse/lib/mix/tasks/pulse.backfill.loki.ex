defmodule Mix.Tasks.Pulse.Backfill.Loki do
  @shortdoc "Prepare one bounded Loki export for replay, without network access"
  @moduledoc """
  Prepare a saved, successful Loki query_range stream response for Pulse ingestion.

      mix pulse.backfill.loki --input export.json --tenant archive \\
        --start-ns 1700000000000000000 --end-ns 1700000001000000000 --limit 5000

  Prints a JSON envelope containing the push body, tenant, content-addressed
  idempotency key and audit bounds. Does not upload anything or start Pulse.
  Bounds are [start, end), in integer nanoseconds. Limit must be the exact limit
  used on the source request. A full response is rejected: split its window or
  stream selector and export again, never advance past a capped timestamp.

  This validates a single batch, not source completeness. Keep the source
  request, response and output immutable; reconcile disjoint windows separately.
  See docs/backfill.md for retention, retry, overlap and approval requirements.
  """
  use Mix.Task

  alias Pulse.Loki.Push

  @max_bytes 4 * 1024 * 1024

  @impl true
  def run(args) do
    %{start_ns: start_ns, end_ns: end_ns, tenant: tenant} = opts = parse_options!(args)
    source = read_source!(opts.input)
    push_streams = source |> decode_response!() |> response_streams!() |> Enum.map(&push_stream!(&1, opts))

    rows = Enum.reduce(push_streams, 0, &(length(&1["values"]) + &2))
    if !(rows < opts.limit), do: Mix.raise("Source response reached its limit; completeness is unknown")

    body = %{"streams" => push_streams}
    encoded = validate_push_body!(body, rows)

    Mix.shell().info(
      JSON.encode!(%{
        "format" => 1,
        "tenant" => tenant,
        "start_ns" => Integer.to_string(start_ns),
        "end_ns" => Integer.to_string(end_ns),
        "rows" => rows,
        "source_sha256" => digest(source),
        "idempotency_key" => "loki-backfill-" <> digest(encoded),
        "body" => body
      })
    )
  end

  defp parse_options!(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          input: [:string, :keep],
          tenant: [:string, :keep],
          start_ns: [:integer, :keep],
          end_ns: [:integer, :keep],
          limit: [:integer, :keep]
        ]
      )

    if !(rest == [] and invalid == [] and
           Enum.sort(Keyword.keys(opts)) == [:end_ns, :input, :limit, :start_ns, :tenant]) do
      Mix.raise("Required exactly once: --input --tenant --start-ns --end-ns --limit")
    end

    opts = Map.new(opts)

    if !(opts.start_ns >= 0 and opts.end_ns > opts.start_ns and opts.end_ns <= 9_223_372_036_854_775_807 and
           opts.limit in 1..10_000 and Regex.match?(~r/\A[A-Za-z0-9_.\-]{1,128}\z/, opts.tenant)) do
      Mix.raise("Invalid tenant, nanosecond bounds or source limit (1..10000)")
    end

    opts
  end

  defp read_source!(path) do
    source = File.open!(path, [:read, :binary], &IO.binread(&1, @max_bytes + 1))
    if !(is_binary(source) and byte_size(source) <= @max_bytes), do: Mix.raise("Export exceeds 4 MiB or is empty")
    source
  end

  defp decode_response!(source) do
    {response, nil, rest} =
      JSON.decode(source, nil,
        object_start: fn _ -> %{} end,
        object_push: fn key, value, acc ->
          if Map.has_key?(acc, key), do: Mix.raise("Duplicate JSON object key in export")
          Map.put(acc, key, value)
        end,
        object_finish: fn acc, old -> {acc, old} end
      )

    if rest != "", do: Mix.raise("Expected one complete JSON export")
    response
  end

  defp response_streams!(
         %{"status" => "success", "data" => %{"resultType" => "streams", "result" => streams}} = response
       )
       when is_list(streams) do
    if Map.get(response, "warnings", []) != [], do: Mix.raise("Source warnings require investigation")
    streams
  end

  defp response_streams!(_), do: Mix.raise("Expected a successful Loki streams response, not samples or a push body")

  defp push_stream!(%{"stream" => labels, "values" => values}, opts) when is_map(labels) and is_list(values) do
    if !string_map?(labels), do: Mix.raise("Stream labels must be strings")
    Enum.each(values, &validate_entry!(&1, opts))
    %{"stream" => labels, "values" => values}
  end

  defp push_stream!(_, _opts), do: Mix.raise("Invalid Loki stream")

  defp validate_entry!(value, %{start_ns: start_ns, end_ns: end_ns}) do
    {timestamp, line, metadata} = entry_parts!(value)

    if !(is_binary(timestamp) and Regex.match?(~r/\A(0|[1-9][0-9]{0,18})\z/, timestamp) and
           is_binary(line) and string_map?(metadata)) do
      Mix.raise("Entries require exact decimal nanoseconds, string lines and string metadata")
    end

    ns = String.to_integer(timestamp)
    if !(ns >= start_ns and ns < end_ns), do: Mix.raise("Entry outside [start-ns, end-ns)")
  end

  defp entry_parts!([timestamp, line]), do: {timestamp, line, %{}}
  defp entry_parts!([timestamp, line, metadata]), do: {timestamp, line, metadata}
  defp entry_parts!(_), do: Mix.raise("Invalid Loki entry")

  defp validate_push_body!(body, rows) do
    case Pulse.IngestLimits.validate(:loki, body) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("Pulse ingest limit: #{inspect(reason)}")
    end

    {records, rejected} = Push.decode(body)
    if !(rejected == 0 and length(records) == rows), do: Mix.raise("Pulse would reject source entries")
    encoded = JSON.encode!(body)
    if !(byte_size(encoded) <= @max_bytes), do: Mix.raise("Push body exceeds 4 MiB")
    encoded
  end

  defp string_map?(map) when is_map(map), do: Enum.all?(map, fn {key, value} -> is_binary(key) and is_binary(value) end)

  defp string_map?(_), do: false
  defp digest(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
