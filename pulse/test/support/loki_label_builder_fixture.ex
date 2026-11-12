defmodule Pulse.Test.LokiLabelBuilderFixture do
  @moduledoc "Public query translations of pinned builder observations, not a Go builder interpreter."

  def load, do: File.read!("test/fixtures/logs/loki-upstream/label-builder.json") |> Pulse.JSON.decode!()
  def table(fixture, name), do: Enum.find(fixture["tables"], &(&1["name"] == name))

  def events(events) do
    Enum.flat_map(events, fn event ->
      [event] ++
        events(event["events"] || []) ++
        Enum.flat_map(event["iterations"] || [], &events(&1["events"]))
    end)
  end

  def assertions(table) do
    for %{"kind" => "assertion", "assertion" => assertion} <- events(table["events"]), do: assertion
  end

  def assertion(table, index), do: Enum.find(assertions(table), &(&1["source_assertion_index"] == index))
  def resolve(%{"kind" => "reference", "resolved" => value}), do: resolve(value)
  def resolve(value), do: value
  def labels(%{"kind" => "reference"} = value), do: value |> resolve() |> labels()
  def labels(%{"kind" => "labels", "labels" => pairs}), do: Map.new(pairs, &{&1["name"], &1["value"]})
  def labels(%{"kind" => "string_map", "value" => value}), do: value

  def base(table) do
    table["events"]
    |> Enum.find(&(&1["kind"] == "assignment" and &1["targets"] == ["lbs"]))
    |> Map.fetch!("values")
    |> hd()
    |> labels()
  end

  def log_cases(fixture) do
    get = table(fixture, "TestLabelsBuilder_Get")
    has = table(fixture, "TestLabelsBuilder_BaseHas")
    into = table(fixture, "TestLabelsBuilder_IntoMap")

    lookups = [
      {"", [{:category, "bar", 0}, {:present, "bar", 1}, {:category, "foo", 3}, {:present, "foo", 4}]},
      {"| drop foo",
       [
         {:present, "foo", 6},
         {:present, "bar", 7},
         {:value, "bar", 8},
         {:category, "bar", 9},
         {:present, "already", 10},
         {:value, "already", 11},
         {:category, "already", 12}
       ]},
      {"| drop foo, bar", [{:present, "bar", 13}]},
      {"| drop foo, bar, already", [{:present, "already", 14}]}
    ]

    for {drop, checks} <- lookups do
      %{
        base: base(get),
        metadata: %{"foo" => "bar"},
        query: ~s'{} | label_format bar="buzz" #{drop}',
        checks:
          Enum.map(checks, fn {kind, key, index} ->
            {kind, key, assertion(get, index)["expected_resolved"]["value"]}
          end)
      }
    end ++
      for {query, checks} <- [
            {"{}", [{:present, "already", 0}, {:present, "missing", 1}]},
            {"{} | drop already", [{:present, "already", 2}]}
          ] do
        %{
          base: base(has),
          metadata: %{},
          query: query,
          checks:
            Enum.map(checks, fn {kind, key, index} ->
              {kind, key, assertion(has, index)["expected_resolved"]["value"]}
            end)
        }
      end ++
      for row <- assertions(into) do
        %{base: base(into), metadata: %{}, query: "{}", checks: [{:labels, nil, labels(row["expected_resolved"])}]}
      end
  end

  def error_case(fixture) do
    source = table(fixture, "TestLabelsBuilder_LabelsErrorFromAdd")
    add = Enum.find(source["events"], &(&1["kind"] == "operation" and &1["operation"] == "Add"))

    %{
      base: base(source),
      metadata: labels(add["call"]["parameters"]["labels"]),
      query: "{}",
      checks:
        for {kind, index} <- [labels: 0, stream: 3, structured_metadata: 4, parsed: 5] do
          {kind, nil, labels(assertion(source, index)["expected_resolved"])}
        end
    }
  end

  def group_cases(fixture) do
    deleted = table(fixture, "TestLabelsBuilder_GroupedLabels_ByAfterDelete")
    grouped = table(fixture, "TestLabelsBuilder_GroupedLabelsResult")

    # Stream Set becomes label_format only for flat grouping observations;
    # its parsed category is not claimed to implement the raw Stream Set API.
    specs = [
      {deleted, 0, "| drop name", "by (name)", %{}},
      {deleted, 1, ~s'| drop name | label_format name="parsed"', "by (name)", %{}},
      {grouped, 0, "", "by (namespace)", %{}},
      {grouped, 2, ~s'| label_format namespace="tempo", buzz="fuzz" | drop job', "by (namespace)", %{"foo" => "bar"}},
      {grouped, 3, ~s'| label_format namespace="tempo", buzz="fuzz" | drop job', "by (namespace)", %{"foo" => "bar"}},
      {grouped, 4, "", "by (job)", %{}},
      {grouped, 5, "", "by (job)", %{}},
      {grouped, 6, "| drop job", "by (job)", %{}},
      {grouped, 7, ~s'| label_format namespace="tempo"', "by (job)", %{}},
      {grouped, 9, "", "by (foo)", %{"foo" => "bar"}},
      {grouped, 11, ~s'| drop job | label_format job="something"', "without (job)", %{"foo" => "bar"}},
      {grouped, 13, "", "without (foo)", %{"foo" => "bar"}},
      {grouped, 15, ~s'| label_format job="something"', nil, %{"foo" => "bar"}}
    ]

    for {source, index, stages, grouping, metadata} <- specs do
      inner = "count_over_time({} #{stages} [1m])"

      %{
        base: base(source),
        metadata: metadata,
        query: if(grouping, do: "sum #{grouping} (#{inner})", else: inner),
        expected: labels(assertion(source, index)["expected_resolved"])
      }
    end
  end

  def preserve_cases(fixture) do
    source = table(fixture, "TestLabelsBuilder_PreserveErrorIsAnOrdinaryLabel")

    for {category, name} <- [
          stream: "StreamLabel",
          structured_metadata: "StructuredMetadataLabel",
          parsed: "ParsedLabel"
        ],
        {grouping, index} <- [{"", 0}, {"without (pod)", 1}, {"by (pod)", 2}] do
      prefix = if category == :parsed, do: ~s'| label_format __preserve_error__="true"', else: ""
      expression = ~s'{} #{prefix} | label_format v="invalid" | unwrap v'

      %{
        base: if(category == :stream, do: %{"pod" => "p1", "__preserve_error__" => "true"}, else: %{"pod" => "p1"}),
        metadata: if(category == :structured_metadata, do: %{"__preserve_error__" => "true"}, else: %{}),
        category: name,
        grouping: grouping,
        expected: assertion(source, index)["expected_resolved"]["value"],
        query: "avg_over_time(#{expression} | __error__!=\"\" [1m]) #{grouping}",
        unpreserved_query: "avg_over_time(#{expression} [1m]) #{grouping}"
      }
    end
  end

  def collision_labels(fixture) do
    fixture["supporting_helpers"]
    |> Enum.find(&(&1["name"] == "collidingLabelPair"))
    |> Map.fetch!("literal_label_bindings")
    |> Enum.map(&labels(&1["labels_expression"]))
  end

  def observation(:labels, _, {stream, extra}),
    do: stream |> Map.merge(extra["structuredMetadata"] || %{}) |> Map.merge(extra["parsed"] || %{})

  def observation(:stream, _, {stream, _}), do: stream
  def observation(:structured_metadata, _, {_, extra}), do: extra["structuredMetadata"] || %{}
  def observation(:parsed, _, {_, extra}), do: extra["parsed"] || %{}
  def observation(:present, name, actual), do: Map.has_key?(observation(:labels, nil, actual), name)
  def observation(:value, name, actual), do: observation(:labels, nil, actual)[name]

  def observation(:category, name, {stream, extra}) do
    cond do
      Map.has_key?(stream, name) -> "StreamLabel"
      Map.has_key?(extra["structuredMetadata"] || %{}, name) -> "StructuredMetadataLabel"
      Map.has_key?(extra["parsed"] || %{}, name) -> "ParsedLabel"
      true -> nil
    end
  end
end
