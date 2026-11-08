defmodule Pulse.Traces.Assembly do
  @moduledoc false
  alias Pulse.Record.Span
  alias Pulse.Record.SpanKey

  @max_bytes 16_777_216

  # Reference renderer. S3 keeps this work in native state instead of expanding
  # candidates on the VM heap. Coverage is a storage snapshot, not exporter
  # completeness: late spans and deliberately unsampled parents may be absent.
  def json(spans, trace_id) do
    cond do
      length(spans) > 5000 -> {:error, :query_sample_limit}
      not Enum.all?(spans, &(&1.trace_id == trace_id)) -> {:error, :invalid_trace_assembly}
      true -> render(spans, trace_id)
    end
  end

  defp render(spans, trace_id) do
    groups = Enum.group_by(spans, & &1.span_id)
    parents = spans |> Enum.map(& &1.parent_span_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    duplicates = for {id, rows} <- groups, length(rows) > 1, do: id
    conflicts = for {id, rows} <- groups, conflicting?(rows), do: id

    result = %{
      "trace_id" => trace_id,
      "coverage" => "all_stored_spans",
      "retention_floor_ns" => nil,
      "span_count" => length(spans),
      "root_span_ids" =>
        spans |> Enum.filter(&is_nil(&1.parent_span_id)) |> Enum.map(& &1.span_id) |> Enum.uniq() |> Enum.sort(),
      "missing_parent_span_ids" => parents |> Enum.reject(&Map.has_key?(groups, &1)) |> Enum.sort(),
      "duplicate_span_ids" => Enum.sort(duplicates),
      "conflicting_span_ids" => Enum.sort(conflicts),
      "metadata_unknown_span_ids" =>
        spans |> Enum.filter(&is_nil(&1.otlp)) |> Enum.map(& &1.span_id) |> Enum.uniq() |> Enum.sort(),
      "spans" => Enum.map(spans, &projection/1)
    }

    binary = Pulse.JSON.encode!(result)
    if byte_size(binary) > @max_bytes, do: {:error, :query_resource_limit}, else: {:ok, binary}
  end

  defp conflicting?([_, _ | _] = rows) do
    projected = Enum.uniq_by(rows, &SpanKey.encode(Map.delete(Span.to_map(&1), "otlp")))
    typed = rows |> Enum.reject(&is_nil(&1.otlp)) |> Enum.uniq_by(&SpanKey.encode(Span.to_map(&1)))
    length(projected) > 1 or length(typed) > 1
  end

  defp conflicting?(_), do: false

  defp projection(span), do: Map.put(Span.to_map(span), "duration_ns", span.end_timestamp_ns - span.timestamp_ns)
end
