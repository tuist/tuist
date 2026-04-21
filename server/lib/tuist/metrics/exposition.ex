defmodule Tuist.Metrics.Exposition do
  @moduledoc """
  Renders metric snapshots in the OpenMetrics text format with a fallback to
  the Prometheus 0.0.4 text format.

  The OpenMetrics spec is a superset of the Prometheus format: it adds `# TYPE`
  suffixes like `_total` for counters, a `# UNIT` line, and a final
  `# EOF` marker. If a client asks for `application/openmetrics-text` we serve
  that; otherwise we serve the plain Prometheus format.
  """

  alias Tuist.Metrics.Schema

  @prometheus_content_type "text/plain; version=0.0.4; charset=utf-8"
  @openmetrics_content_type "application/openmetrics-text; version=1.0.0; charset=utf-8"

  @doc """
  Returns the content type header for a given format.
  """
  def content_type(:openmetrics), do: @openmetrics_content_type
  def content_type(:prometheus), do: @prometheus_content_type

  @doc """
  Picks a response format from an `Accept` header.

  The `Accept` header for Prometheus scrapes is typically
  `application/openmetrics-text;...,text/plain;...;q=0.2,*/*;q=0.1` — we pick
  OpenMetrics when the client explicitly asks for it, otherwise fall back to
  the classic Prometheus format.
  """
  def negotiate(accept_header) when is_binary(accept_header) do
    if String.contains?(accept_header, "application/openmetrics-text") do
      :openmetrics
    else
      :prometheus
    end
  end

  def negotiate(_), do: :prometheus

  @doc """
  Renders a list of metric snapshots as an IO list in the selected format.

  The snapshot is re-indexed by metric name so all observations under the same
  name appear as a contiguous block, preceded by a single `# HELP` / `# TYPE`
  pair. This is required by both Prometheus and OpenMetrics parsers.
  """
  def render(snapshot, format) when format in [:prometheus, :openmetrics] do
    indexed = group_by_metric(snapshot)

    body =
      Schema.definitions()
      |> Enum.map(&render_metric(&1, Map.get(indexed, &1.name, []), format))

    case format do
      :openmetrics -> [body, "# EOF\n"]
      :prometheus -> body
    end
  end

  # ---- Metric rendering --------------------------------------------------

  defp render_metric(%{name: name, type: :counter, help: help, labels: label_keys}, entries, format) do
    # OpenMetrics' counter families name the family without the `_total`
    # suffix — the suffix only appears on sample lines. Our schema already
    # ends counter names in `_total` so we strip it for OpenMetrics HELP/TYPE
    # lines and always use `name` for samples, matching the Prometheus 0.0.4
    # convention scrapers rely on.
    family_name = if format == :openmetrics, do: strip_total_suffix(name), else: name

    [
      "# HELP ",
      family_name,
      " ",
      escape_help(help),
      "\n",
      "# TYPE ",
      family_name,
      " counter\n",
      Enum.map(entries, &render_counter_line(&1, name, label_keys, format))
    ]
  end

  defp render_metric(%{name: name, type: :histogram, help: help, labels: label_keys}, entries, format) do
    [
      "# HELP ",
      name,
      " ",
      escape_help(help),
      "\n",
      "# TYPE ",
      name,
      " histogram\n",
      Enum.map(entries, &render_histogram(&1, name, label_keys, format))
    ]
  end

  defp render_counter_line(%{labels: labels, value: value}, name, label_keys, _format) do
    # Schema names already end in `_total`. Both Prometheus 0.0.4 and
    # OpenMetrics want exactly one `_total` suffix on the sample line, so we
    # emit the schema name verbatim.
    [name, render_labels(label_keys, labels), " ", format_integer(value), "\n"]
  end

  defp strip_total_suffix("tuist_" <> _ = name) do
    if String.ends_with?(name, "_total") do
      String.slice(name, 0, byte_size(name) - byte_size("_total"))
    else
      name
    end
  end

  defp strip_total_suffix(name), do: name

  defp render_histogram(
         %{labels: labels, count: count, sum: sum, buckets: buckets},
         name,
         label_keys,
         _format
       ) do
    label_tuple = labels

    cumulative =
      buckets
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {bound, bucket_count} ->
        [
          name,
          "_bucket",
          render_labels_with_extra(label_keys, label_tuple, {:le, format_bucket(bound)}),
          " ",
          format_integer(bucket_count),
          "\n"
        ]
      end)

    [
      cumulative,
      name,
      "_bucket",
      render_labels_with_extra(label_keys, label_tuple, {:le, "+Inf"}),
      " ",
      format_integer(count),
      "\n",
      name,
      "_sum",
      render_labels(label_keys, label_tuple),
      " ",
      format_float(sum),
      "\n",
      name,
      "_count",
      render_labels(label_keys, label_tuple),
      " ",
      format_integer(count),
      "\n"
    ]
  end

  # ---- Labels ------------------------------------------------------------

  defp render_labels([], _labels), do: ""

  defp render_labels(label_keys, label_tuple) do
    pairs =
      label_keys
      |> Enum.with_index()
      |> Enum.map(fn {key, idx} -> label_pair(key, elem(label_tuple, idx)) end)

    ["{", Enum.intersperse(pairs, ","), "}"]
  end

  defp render_labels_with_extra(label_keys, label_tuple, {extra_key, extra_value}) do
    base_pairs =
      label_keys
      |> Enum.with_index()
      |> Enum.map(fn {key, idx} -> label_pair(key, elem(label_tuple, idx)) end)

    extra_pair = label_pair(extra_key, extra_value)

    ["{", Enum.intersperse(base_pairs ++ [extra_pair], ","), "}"]
  end

  defp label_pair(key, value) do
    [Atom.to_string(key), "=\"", escape_label(to_string(value)), "\""]
  end

  # ---- Grouping and formatting ------------------------------------------

  defp group_by_metric(snapshot) do
    Enum.group_by(snapshot, & &1.metric)
  end

  defp format_integer(value) when is_integer(value), do: Integer.to_string(value)
  defp format_integer(value) when is_float(value), do: Integer.to_string(trunc(value))

  defp format_float(value) when is_integer(value), do: Integer.to_string(value)

  defp format_float(value) when is_float(value) do
    # Prometheus text format accepts either decimals or scientific notation.
    # `:erlang.float_to_binary/2` with `[:short]` gives the smallest lossless
    # representation.
    :erlang.float_to_binary(value, [:short])
  end

  defp format_bucket(bound) when is_integer(bound), do: Integer.to_string(bound)
  defp format_bucket(bound) when is_float(bound), do: :erlang.float_to_binary(bound, [:short])

  defp escape_help(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("\n", "\\n")
  end

  defp escape_label(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end
end
