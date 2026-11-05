defmodule Pulse.Test.LokiSampleExtractorFixture do
  @moduledoc "Public query translations of frozen sample observations, not a Go extractor interpreter."

  def load, do: File.read!("test/fixtures/logs/loki-upstream/sample-extractors.json") |> Pulse.JSON.decode!()
  def labels(pairs), do: Map.new(pairs, &{&1["name"], &1["value"]})

  def cases(fixture) do
    for source <- fixture["executions"] do
      extractor = source["extractor"]
      expected_labels = if source["expected_labels"], do: labels(source["expected_labels"])
      metadata = labels(source["structured_metadata"])
      preserve? = Map.has_key?(expected_labels || %{}, "__error__") or Map.has_key?(metadata, "__error__")
      stages = Enum.map_join(extractor["stages"], " ", &stage/1)
      query = query(extractor, stages, preserve?)

      %{
        id: source["execution_id"],
        function: source["source_function"],
        base: labels(source["stream_labels"]),
        metadata: metadata,
        line: Base.decode64!(source["line_bytes_base64"]),
        query: query,
        unpreserved_query: if(preserve? and source["expected_ok"], do: query(extractor, stages, false)),
        expected_ok: source["expected_ok"],
        expected_value: source["expected_value"],
        expected_labels: expected_labels,
        distinct?: extractor["constructor"] == "NewDistinctValueSampleExtractor"
      }
    end
  end

  defp query(%{"constructor" => "LabelExtractorWithStages"} = ex, stages, preserve?) do
    label = ex["label"]

    value =
      case ex["conversion"] do
        "ConvertFloat" -> label
        "ConvertDuration" -> "duration(#{label})"
        "ConvertBytes" -> "bytes(#{label})"
      end

    post = stage(ex["post_filter"])
    errors = if preserve?, do: ~s'| __error__!=""', else: ""
    "avg_over_time({} #{stages} | unwrap #{value} #{post} #{errors} [1m]) #{grouping(ex)}"
  end

  defp query(%{"constructor" => "NewDistinctValueSampleExtractor"} = ex, stages, false) do
    # The source encodes xxhash bits as a float. Public distinct counting
    # checks presence/grouping; its cardinality is an authored control.
    group = if ex["without"], do: "", else: grouping(ex)
    "approx_count_distinct(#{ex["label"]}, {} #{stages} [1m]) #{group}"
  end

  defp query(%{"constructor" => constructor} = ex, stages, preserve?)
       when constructor in ["NewLineSampleExtractor", "builderExtractor"] do
    op = if ex["conversion"] == "BytesExtractor", do: "bytes_over_time", else: "count_over_time"
    errors = if preserve?, do: ~s'| __error__!=""', else: ""
    inner = "#{op}({} #{stages} #{errors} [1m])"
    group = grouping(ex, preserve?)
    if group == "", do: inner, else: "sum #{group} (#{inner})"
  end

  defp grouping(ex, preserve? \\ false) do
    names = ex["groups"] || []

    cond do
      ex["no_labels"] -> "by ()"
      ex["without"] -> "without (#{Enum.join(names, ",")})"
      names == [] -> ""
      preserve? -> "by (#{Enum.join(names ++ ["__error__", "__error_details__"], ",")})"
      true -> "by (#{Enum.join(names, ",")})"
    end
  end

  defp stage(%{"kind" => "symbolic_identifier", "name" => "NoopStage"}), do: ""
  defp stage(%{"constructor" => "NewLogfmtParser", "arguments" => [false, false]}), do: "| logfmt"
  defp stage(%{"constructor" => "NewJSONParser", "arguments" => [false]}), do: "| json"

  defp stage(%{"constructor" => "NewStringLabelFilter", "arguments" => [matcher]}) do
    [op, name, value] = matcher["arguments"]
    operator = %{"MatchEqual" => "=", "MatchNotEqual" => "!="}[op["name"]]
    "| #{name}#{operator}#{Pulse.JSON.encode!(value)}"
  end

  defp stage(%{
         "constructor" => "NewNumericLabelFilter",
         "arguments" => [%{"name" => "LabelFilterNotEqual"}, name, value]
       }), do: "| #{name}!=#{value}"

  defp stage(%{
         "constructor" => "ToStage",
         "receiver" => %{
           "constructor" => "mustFilter",
           "arguments" => [%{"constructor" => "NewFilter", "arguments" => [value, %{"name" => "LineMatchEqual"}]}]
         }
       }), do: "|= #{Pulse.JSON.encode!(value)}"

  defp stage(%{
         "constructor" => "NewLabelsFormatter",
         "arguments" => [[%{"constructor" => "NewRenameLabelFmt", "arguments" => [destination, source]}]]
       }), do: "| label_format #{destination}=#{source}"
end
