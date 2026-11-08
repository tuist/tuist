defmodule Pulse.Alerting.NativeExpression do
  @moduledoc "Explicit native instant-source conditions, not executable Grafana imports."
  alias Pulse.Alerting.Expressions
  alias Pulse.Alerting.Expressions.Math
  alias Pulse.Alerting.GraphPreview
  alias Pulse.LogQL.AST.LogQuery
  alias Pulse.LogQL.QueryValidation
  alias Pulse.PromQL.Evaluator
  alias Pulse.PromQL.Number
  alias Pulse.PromQL.Parser

  @terminal "__condition"
  def validate(%{"sources" => sources, "expression" => expression} = rule)
      when is_list(sources) and length(sources) in 1..16 and is_binary(expression) do
    with true <- Enum.all?(sources, &source?/1),
         refs = Enum.map(sources, & &1["ref"]),
         true <- length(Enum.uniq(refs)) == length(refs),
         {:ok, _, _, used} <- Math.parse(expression),
         true <- Enum.sort(used) == Enum.sort(refs),
         {:ok, _} <- Expressions.compile(plan(rule)) do
      :ok
    else
      _ -> {:error, :invalid_expression_rule}
    end
  end

  def validate(_), do: {:error, :invalid_expression_rule}

  defp source?(%{"ref" => ref, "language" => language, "query" => query} = source) do
    Map.keys(source) -- ~w(ref language query empty_value) == [] and
      empty_value?(source) and ref?(ref) and language in ["promql", "logql"] and
      is_binary(query) and byte_size(query) in 1..16_384 and String.valid?(query) and valid_query?(language, query)
  end

  defp source?(_), do: false
  defp empty_value?(%{"empty_value" => 0}), do: true
  defp empty_value?(source), do: not Map.has_key?(source, "empty_value")
  defp ref?(ref), do: is_binary(ref) and ref != @terminal and Regex.match?(~r/\A[a-zA-Z_][a-zA-Z0-9_]{0,127}\z/, ref)

  defp valid_query?("promql", query) do
    case Parser.parse(query) do
      {:ok, ast} -> Parser.type(ast) in [:scalar, :vector]
      _ -> false
    end
  end

  defp valid_query?("logql", query) do
    with {:ok, ast} <- Pulse.LogQL.Parser.parse(query),
         false <- match?(%LogQuery{}, ast),
         :ok <- QueryValidation.validate(ast),
         do: true,
         else: (_ -> false)
  end

  def query(rule, tenant, opts) do
    with :ok <- validate(rule) do
      sources = Enum.map(rule["sources"], &source_query(&1, opts.end_ts_ns))
      Evaluator.query_batch(sources, tenant, &finish(rule, &1, &2), opts)
    end
  end

  defp source_query(source, time) do
    language = if source["language"] == "logql", do: :logql, else: :promql
    {source["ref"], source["query"], %{end_ts_ns: time, language: language}}
  end

  defp plan(rule) do
    sources = Enum.map(rule["sources"], &%{"refId" => &1["ref"], "datasourceUid" => "native", "model" => %{}})

    condition = %{
      "refId" => @terminal,
      "datasourceUid" => "__expr__",
      "model" => %{"type" => "math", "expression" => rule["expression"]}
    }

    %{"condition" => @terminal, "data" => sources ++ [condition]}
  end

  defp finish(rule, results, deadline) do
    with {:ok, inputs} <- GraphPreview.inputs(results),
         inputs = empty_values(rule["sources"], inputs),
         {:ok, graph} <- Expressions.execute(plan(rule), inputs, deadline: deadline),
         true <- graph.notices == [],
         {:ok, samples} <- samples(graph.terminal) do
      {:ok, %{"data" => %{"resultType" => "vector", "result" => samples}}}
    else
      false -> {:error, :expression_label_loss}
      error -> error
    end
  end

  # Only a successful, fully empty instant vector can become an explicitly
  # authored scalar zero. Errors, missing authority and partial label sets cannot.
  defp empty_values(sources, inputs) do
    Enum.reduce(sources, inputs, fn source, acc ->
      if source["empty_value"] === 0 and acc[source["ref"]] == {:numbers, []},
        do: Map.put(acc, source["ref"], {:scalar, 0.0}),
        else: acc
    end)
  end

  defp samples({:scalar, value}), do: samples({:numbers, [%{labels: %{}, value: value}]})

  defp samples({:numbers, frames}) when length(frames) <= 128 do
    {:ok, Enum.map(frames, &%{"metric" => &1.labels, "value" => [0, value(&1.value)]})}
  end

  defp samples({:numbers, _}), do: {:error, :instance_limit}
  defp samples(_), do: {:error, :invalid_query_result}
  defp value(number) when is_number(number), do: to_string(number)
  defp value(nil), do: "null"
  defp value(number), do: Number.format(number)
end
