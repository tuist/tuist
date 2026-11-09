defmodule Pulse.Storage.SortOrder do
  @moduledoc """
  Canonical sort order for a query result, per signal. Every storage
  adapter must apply this so a client that switches adapters — or fans a
  query out to more than one — cannot observe the tiebreaker changing.

  ## Logs

  Primary key: `timestamp_ns` descending (newest first).
  Tiebreakers, in order: `observed_timestamp_ns` desc, `trace_id`,
  `span_id`, `body`. `nil` sorts last within its position.

  ## Metrics

  Primary key: `timestamp_ns` descending (newest sample first).
  Tiebreakers, in order: `series_id` desc, then a canonical stringified
  label-set and sample value. `nil` sorts last within its position. This matches
  what a
  PromQL evaluator expects at the output boundary: samples bucketed by
  time, with a deterministic series order within each timestamp.

  ## Traces

  Start timestamp descending, then trace ID and span ID descending. Complete
  deterministic metadata bytes break ties without conflating typed metadata values.
  The native top-k selector uses the same key before allocating Erlang records.
  """

  alias Pulse.Record.Log
  alias Pulse.Record.MetricSample
  alias Pulse.Record.Span
  alias Pulse.Record.SpanKey

  @spec sort([Pulse.Storage.signal_record()], Pulse.Storage.signal()) :: [Pulse.Storage.signal_record()]
  def sort(records, :logs), do: Enum.sort_by(records, &log_sort_key/1, &compare_desc/2)
  def sort(records, :metrics), do: Enum.sort_by(records, &metric_sort_key/1, &compare_desc/2)

  def sort(records, :traces), do: Enum.sort(records, &span_before?/2)

  @doc false
  def merge_spans(left, right, limit), do: merge_spans(left, right, limit, [])
  defp merge_spans(_left, _right, 0, acc), do: Enum.reverse(acc)
  defp merge_spans([], right, limit, acc), do: Enum.reverse(acc, Enum.take(right, limit))
  defp merge_spans(left, [], limit, acc), do: Enum.reverse(acc, Enum.take(left, limit))

  defp merge_spans([a | as] = left, [b | bs] = right, limit, acc) do
    if span_before?(a, b),
      do: merge_spans(as, right, limit - 1, [a | acc]),
      else: merge_spans(left, bs, limit - 1, [b | acc])
  end

  @doc "Logs-signal convenience; retained for callers that have not been taught signal dispatch."
  @spec sort([Log.t()]) :: [Log.t()]
  def sort(records) when is_list(records), do: sort(records, :logs)

  # Each string-shaped tiebreaker becomes `{presence_flag, value}` so a nil
  # sorts *after* every real string in descending order, and — crucially —
  # never collapses with an empty string.
  defp log_sort_key(%Log{} = r) do
    {
      r.timestamp_ns || 0,
      r.observed_timestamp_ns || 0,
      presence_pair(r.trace_id),
      presence_pair(r.span_id),
      presence_pair(r.body),
      :erlang.term_to_binary(Map.from_struct(r), [:deterministic])
    }
  end

  defp span_before?(%Span{} = a, %Span{} = b) do
    left = {a.timestamp_ns, a.trace_id, a.span_id}
    right = {b.timestamp_ns, b.trace_id, b.span_id}

    if left == right do
      a === b or SpanKey.encode(Span.to_map(a)) >= SpanKey.encode(Span.to_map(b))
    else
      left > right
    end
  end

  defp metric_sort_key(%MetricSample{} = s) do
    {
      s.timestamp_ns || 0,
      s.series_id || 0,
      canonical_labels(s.labels),
      sample_value_key(s.value),
      :erlang.term_to_binary(Map.from_struct(s), [:deterministic])
    }
  end

  defp sample_value_key(nil), do: {0, 0}
  defp sample_value_key(value), do: {1, value}

  # Deterministic string form of a label map, used only as a tiebreaker.
  # Sorting the keys makes it stable across the two Elixir map
  # implementations (small-flat vs big-hash).
  defp canonical_labels(labels) when is_map(labels) do
    labels
    |> Enum.sort()
    |> Enum.map_join("\0", fn {k, v} -> "#{k}=#{v}" end)
  end

  defp canonical_labels(_), do: ""

  # Body's readable prefix keeps the historical ordering. The final complete
  # typed record key resolves inspect/metadata ties without conflating signed
  # zero, bytes/string tags, or distinct scope/resource attributes.
  defp presence_pair(nil), do: {0, ""}
  defp presence_pair(value) when is_binary(value), do: {1, value}
  defp presence_pair(value), do: {1, inspect(value)}

  defp compare_desc(a, b), do: a >= b

  @doc false
  # The complete log sort key, for callers that order records they receive in
  # batches exactly as `sort/2` would order one list.
  def log_key(%Log{} = record), do: log_sort_key(record)
end
