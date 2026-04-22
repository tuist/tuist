defmodule Tuist.Metrics.Schema.Markdown do
  @moduledoc """
  Renders `Tuist.Metrics.Schema` as Markdown.

  The user-facing metrics reference docs page embeds the output via a
  `{{TUIST_METRICS_TABLE}}` marker, which `Tuist.Docs.Loader` substitutes
  at page-compile time. Doing the render from the schema means the docs
  can never drift from what the scrape endpoint actually exposes.
  """

  alias Tuist.Metrics.Schema

  @doc """
  Renders the metric catalogue as a Markdown fragment with a section per
  namespace.
  """
  def render do
    Schema.definitions()
    |> Enum.group_by(& &1.namespace)
    |> Enum.sort_by(fn {namespace, _} -> namespace_order(namespace) end)
    |> Enum.map_join("\n\n", fn {namespace, defs} ->
      render_namespace(namespace, defs)
    end)
  end

  defp render_namespace(namespace, defs) do
    [
      "### ",
      namespace |> to_string() |> String.capitalize(),
      "\n\n",
      Enum.map_join(defs, "\n\n", &render_metric/1)
    ]
    |> IO.iodata_to_binary()
  end

  defp render_metric(%{
         name: name,
         type: type,
         help: help,
         labels: labels
       } = metric) do
    lines =
      [
        "#### `#{name}` {##{anchor(name)}}",
        "",
        help,
        "",
        "- **Type:** #{type}",
        "- **Labels:** #{format_labels(labels)}"
      ] ++ histogram_lines(metric)

    Enum.join(lines, "\n")
  end

  defp histogram_lines(%{type: :histogram, buckets: buckets}) do
    ["- **Buckets (seconds):** #{Enum.map_join(buckets, ", ", &format_bucket/1)}"]
  end

  defp histogram_lines(_), do: []

  defp format_labels([]), do: "_none_"

  defp format_labels(labels),
    do: Enum.map_join(labels, ", ", fn label -> "`#{label}`" end)

  defp format_bucket(bound) when is_integer(bound), do: "`#{bound}`"

  defp format_bucket(bound) when is_float(bound) do
    if bound == Float.floor(bound) do
      "`#{trunc(bound)}`"
    else
      "`#{:erlang.float_to_binary(bound, [:short])}`"
    end
  end

  defp anchor(metric_name), do: String.replace(metric_name, "_", "-")

  # Xcode first, then Gradle, then CLI. Any future namespaces fall to the end.
  defp namespace_order(:xcode), do: 0
  defp namespace_order(:gradle), do: 1
  defp namespace_order(:cli), do: 2
  defp namespace_order(_), do: 99
end
