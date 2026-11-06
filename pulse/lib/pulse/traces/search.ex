defmodule Pulse.Traces.Search do
  @moduledoc "Reference window-local trace grouping for single-spanset string selectors, not a Tempo envelope."

  alias Pulse.Codec.NIF
  alias Pulse.OTLP.Value

  def json(spans, predicates, opts) do
    with {:ok, groups} <- group(spans, predicates, opts) do
      matching = groups |> Map.values() |> Enum.filter(&(&1["matching_span_count"] > 0))

      rows =
        matching
        |> Enum.sort_by(&{-&1["start_timestamp_ns"], &1["trace_id"]})
        |> Enum.take(Keyword.get(opts, :limit, 100))
        |> Enum.map(&Map.put(&1, "duration_ns", &1["end_timestamp_ns"] - &1["start_timestamp_ns"]))

      {:ok,
       Pulse.JSON.encode!(%{
         "coverage" => "window_stored_spans",
         "effective_start_ts_ns" => opts[:start_ts],
         "end_ts_ns" => opts[:end_ts],
         "matched_trace_count" => length(matching),
         "traces" => rows
       })}
    end
  end

  defp group(spans, predicates, opts) do
    Enum.reduce_while(spans, {:ok, %{}}, fn span, {:ok, groups} ->
      add_group(span, groups, predicates, opts)
    end)
  end

  defp add_group(span, groups, predicates, opts) do
    with :ok <- deadline(opts),
         :ok <- metadata(span),
         true <- Map.has_key?(groups, span.trace_id) or map_size(groups) < Keyword.get(opts, :max_trace_groups, 65_536) do
      group = %{
        "trace_id" => span.trace_id,
        "start_timestamp_ns" => span.timestamp_ns,
        "end_timestamp_ns" => span.end_timestamp_ns,
        "stored_span_count" => 1,
        "matching_span_count" => if(matches?(span, predicates), do: 1, else: 0)
      }

      {:cont, {:ok, Map.update(groups, span.trace_id, group, &merge(&1, group))}}
    else
      false -> {:halt, {:error, :trace_group_limit}}
      {:error, _} = error -> {:halt, error}
    end
  end

  defp merge(old, new) do
    %{
      old
      | "start_timestamp_ns" => min(old["start_timestamp_ns"], new["start_timestamp_ns"]),
        "end_timestamp_ns" => max(old["end_timestamp_ns"], new["end_timestamp_ns"]),
        "stored_span_count" => old["stored_span_count"] + 1,
        "matching_span_count" => old["matching_span_count"] + new["matching_span_count"]
    }
  end

  defp matches?(span, predicates) do
    Enum.all?(predicates, fn {scope, key, op, wanted} ->
      owner = if scope == "resource", do: "resource", else: "attributes"
      pair = Enum.find(span.otlp[owner], &(&1["key"] == key))

      match_pair?(pair, op, wanted)
    end)
  end

  defp match_pair?(%{"value" => %{"stringValue" => value}}, "=", wanted), do: value == wanted

  defp match_pair?(%{"value" => %{"stringValue" => value}}, "=~", wanted),
    do: NIF.match_metric_regex(Pulse.QueryRegex.anchor(wanted), value)

  defp match_pair?(_, _, _), do: false

  @doc false
  def validate_metadata(span), do: metadata(span)

  defp metadata(%{otlp: nil}), do: {:error, :trace_metadata_unknown}

  defp metadata(span) do
    typed = span.otlp

    valid? =
      valid_envelope?(typed) and valid_identity?(span) and
        owners?(typed["events"], span.events) and owners?(typed["links"], span.links)

    if valid?, do: :ok, else: {:error, {:decode_failed, :parquet_decoder_rejected_input}}
  end

  defp valid_envelope?(typed) do
    is_map(typed) and map_size(typed) == 6 and typed["version"] === 1 and
      Enum.all?(~w(resource scope attributes), &attributes?(typed[&1]))
  end

  defp valid_identity?(span) do
    is_binary(span.trace_id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, span.trace_id) and
      span.trace_id != String.duplicate("0", 32) and valid_times?(span)
  end

  defp valid_times?(span) do
    is_integer(span.timestamp_ns) and span.timestamp_ns >= 0 and
      is_integer(span.end_timestamp_ns) and span.end_timestamp_ns >= span.timestamp_ns and
      span.end_timestamp_ns <= 9_223_372_036_854_775_807
  end

  defp owners?(owners, spans) when is_list(owners) and is_list(spans),
    do: length(owners) == length(spans) and Enum.all?(owners, &attributes?/1)

  defp owners?(_, _), do: false

  defp attributes?(pairs) when is_list(pairs) do
    with true <- Enum.all?(pairs, &closed_pair?/1),
         {:ok, _, normalized} <- Value.attributes(%{"attributes" => pairs}) do
      normalized == pairs
    else
      _ -> false
    end
  end

  defp attributes?(_), do: false
  defp closed_pair?(%{"key" => _, "value" => value} = pair), do: map_size(pair) == 2 and numeric_double?(value)
  defp closed_pair?(_), do: false

  defp numeric_double?(%{"doubleValue" => value}), do: is_number(value) or value in ["NaN", "Infinity", "-Infinity"]

  defp numeric_double?(%{"arrayValue" => %{"values" => values}}) when is_list(values),
    do: Enum.all?(values, &numeric_double?/1)

  defp numeric_double?(%{"kvlistValue" => %{"values" => pairs}}) when is_list(pairs),
    do: Enum.all?(pairs, &closed_pair?/1)

  defp numeric_double?(_), do: true

  defp deadline(opts) do
    if is_integer(opts[:deadline_ms]) and System.monotonic_time(:millisecond) >= opts[:deadline_ms],
      do: {:error, :query_timeout},
      else: :ok
  end
end
