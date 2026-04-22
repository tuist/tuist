defmodule Tuist.Metrics.Schema.MarkdownTest do
  use ExUnit.Case, async: true

  alias Tuist.Metrics.Schema
  alias Tuist.Metrics.Schema.Markdown

  describe "render/0" do
    setup do
      %{output: Markdown.render()}
    end

    test "emits a namespace heading for each schema namespace", %{output: output} do
      namespaces = Schema.definitions() |> Enum.map(& &1.namespace) |> Enum.uniq()

      for namespace <- namespaces do
        expected = "### " <> String.capitalize(to_string(namespace))
        assert output =~ expected
      end
    end

    test "every metric in the schema has a heading and a stable anchor", %{output: output} do
      for %{name: name} <- Schema.definitions() do
        anchor = String.replace(name, "_", "-")

        assert output =~ "#### `#{name}` {##{anchor}}",
               "Expected heading for #{name} with anchor #{anchor} in rendered markdown"
      end
    end

    test "counters list their labels, histograms additionally list their buckets", %{output: output} do
      for metric <- Schema.definitions() do
        case metric do
          %{type: :histogram, labels: labels, buckets: buckets} ->
            assert output =~ "- **Type:** histogram"
            assert output =~ "- **Labels:** #{format_labels(labels)}"
            # At least one bucket boundary mention — the rendering formats
            # floats concisely, so sample the first one.
            first = hd(buckets)
            assert output =~ format_bucket(first)

          %{type: :counter, labels: labels} ->
            assert output =~ "- **Type:** counter"
            assert output =~ "- **Labels:** #{format_labels(labels)}"
        end
      end
    end

    test "Xcode heading appears before Gradle and CLI", %{output: output} do
      xcode = output |> :binary.match("### Xcode") |> elem(0)
      gradle = output |> :binary.match("### Gradle") |> elem(0)
      cli = output |> :binary.match("### Cli") |> elem(0)

      assert xcode < gradle
      assert gradle < cli
    end
  end

  defp format_labels(labels), do: Enum.map_join(labels, ", ", fn label -> "`#{label}`" end)

  defp format_bucket(bound) when is_integer(bound), do: "`#{bound}`"

  defp format_bucket(bound) when is_float(bound) do
    if bound == Float.floor(bound), do: "`#{trunc(bound)}`", else: "`#{bound}`"
  end
end
