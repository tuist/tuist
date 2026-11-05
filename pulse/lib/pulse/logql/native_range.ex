defmodule Pulse.LogQL.NativeRange do
  @moduledoc """
  Native input for streamed range aggregations.

  For a range aggregation whose pipeline uses only line filters, `logfmt`,
  `regexp`, string/regex/number label filters and a plain `unwrap`, the
  storage scan runs the pipeline in Rust and returns one packed, ordered
  sample list per series, without building Erlang terms for log records.
  It answers exactly as `Pulse.LogQL.MetricEval`'s Elixir pipeline would;
  any query or row it cannot reproduce returns `:fallback` and the caller
  evaluates in Elixir. Adapters without native scans also fall back.
  """

  alias Pulse.Codec.NIF
  alias Pulse.LogQL.AST
  alias Pulse.LogQL.Evaluator
  alias Pulse.LogQL.Pipeline
  alias Pulse.LogQL.QueryValidation
  alias Pulse.LogQL.StreamMatchers
  alias Pulse.PromQL.Evaluator, as: Budget
  alias Pulse.Storage

  @ops ~w(count_over_time rate bytes_over_time bytes_rate sum_over_time avg_over_time min_over_time
          max_over_time stddev_over_time stdvar_over_time quantile_over_time)a

  @doc """
  `{:ok, %{labels => {:packed, samples}}}`, `{:error, reason}`, or
  `:fallback` when the query or its data needs the Elixir pipeline.
  """
  def collect(inner, spec, tenant, query_opts) do
    case binned(inner, spec, tenant, query_opts) do
      :skip -> collect_samples(inner, spec, tenant, query_opts)
      result -> result
    end
  end

  @binned_ops [:count_over_time, :bytes_over_time, :rate, :bytes_rate]

  # Line and byte counts over minute-aligned windows of a plain selector sum
  # per-minute bins, read from log rollups where valid and from lines
  # elsewhere (`Pulse.Storage.log_binned_scan/3`). Each series' samples are
  # `{:binned, packed}`: one `{bucket_end, count | bytes}` per minute.
  defp binned(inner, spec, tenant, query_opts) do
    with true <- Map.get(spec, :binnable, false),
         true <- spec.op in @binned_ops and is_nil(spec.unwrap),
         true <- Map.get(spec, :post_filter, []) == [] and not Map.get(spec, :preserve_errors, false),
         true <- Storage.native_log_binned?(),
         :ok <- QueryValidation.validate(inner),
         {storage_opts, []} <- Evaluator.push_down(inner, query_opts),
         false <- Keyword.has_key?(storage_opts, :line_filters),
         {:ok, scan} <-
           native(
             NIF.log_metric_binned_new(binned_value(spec.op), grouping(spec.grouping), Budget.remaining(:log_samples))
           ) do
      case scan(tenant, storage_opts, scan, &Storage.log_binned_scan/3) do
        {:ok, series} -> {:ok, Map.new(series, fn {labels, {:packed, packed}} -> {labels, {:binned, packed}} end)}
        other -> other
      end
    else
      {:error, _} = error -> error
      _ -> :skip
    end
  end

  defp binned_value(op) when op in [:bytes_over_time, :bytes_rate], do: :bytes
  defp binned_value(_op), do: :count

  defp collect_samples(inner, spec, tenant, query_opts) do
    with true <- spec.op in @ops,
         {:ok, drop_errors?} <- post_filter(Map.get(spec, :post_filter, []), spec),
         false <- Map.get(spec, :preserve_errors, false),
         true <- Storage.native_log_metric?(),
         :ok <- QueryValidation.validate(inner),
         {storage_opts, stages} = Evaluator.push_down(inner, query_opts),
         {:ok, program} <- encode_stages(stages),
         {:ok, value} <- value(spec, drop_errors?),
         {:ok, scan} <-
           native(
             NIF.log_metric_scan_new(
               program,
               value,
               drop(spec),
               grouping(spec.grouping),
               Budget.remaining(:log_samples)
             )
           ) do
      scan(tenant, storage_opts, scan, &Storage.log_metric_scan/3)
    else
      {:error, _} = error -> error
      _ -> :fallback
    end
  end

  defp scan(tenant, storage_opts, scan, read) do
    case read.(tenant, storage_opts, scan) do
      {:ok, {selected, kept}} ->
        Budget.charge(:log_samples, kept)
        Budget.charge(:work, selected)
        {:ok, decode(NIF.log_metric_scan_finish(scan))}

      {:error, :pipeline_error} ->
        throw({:logql_error, :pipeline_error})

      {:error, :query_resource_limit} ->
        _ = NIF.log_metric_scan_abort(scan)
        {:error, :query_sample_limit}

      {:error, :native_fallback} ->
        _ = NIF.log_metric_scan_abort(scan)
        :fallback

      {:error, _} = error ->
        _ = NIF.log_metric_scan_abort(scan)
        error
    end
  end

  # Packed samples stay off the process heap; windows decode their slices.
  defp decode({:ok, series}), do: Map.new(series, fn {labels, packed} -> {labels, {:packed, packed}} end)

  defp native({:ok, scan}), do: {:ok, scan}
  defp native(_), do: :fallback

  # Post-unwrap `__error__=""` filters only drop errored observations, which
  # the native scan does itself; any other post-unwrap stage runs in Elixir.
  defp post_filter([], _spec), do: {:ok, false}

  defp post_filter(filters, %{unwrap: %AST.Unwrap{}}) do
    error_free = Pipeline.compile([%AST.LabelFilter{expr: {:cmp, "__error__", :eq, {:string, ""}}}])
    if Enum.all?(filters, &(&1 in error_free)), do: {:ok, true}, else: :fallback
  end

  defp post_filter(_filters, _spec), do: :fallback

  defp value(spec, false), do: value(spec)

  defp value(spec, true) do
    case value(spec) do
      {:ok, {:unwrap, label}} -> {:ok, {:unwrap, label, :drop_errors}}
      _ -> :fallback
    end
  end

  defp value(%{op: op}) when op in [:bytes_over_time, :bytes_rate], do: {:ok, :bytes}
  defp value(%{op: :count_over_time}), do: {:ok, :count}
  defp value(%{unwrap: nil}), do: {:ok, :count}
  defp value(%{unwrap: %AST.Unwrap{label: label, conversion: :none}}), do: {:ok, {:unwrap, label}}
  defp value(_), do: :fallback

  defp drop(%{unwrap: %AST.Unwrap{label: label}}), do: label
  defp drop(_), do: nil

  defp grouping(nil), do: nil
  defp grouping(%AST.Grouping{mode: mode, labels: labels}), do: {mode, labels}

  defp encode_stages(stages) do
    Enum.reduce_while(stages, {:ok, []}, fn stage, {:ok, acc} ->
      case stage(stage) do
        nil -> {:halt, :fallback}
        encoded -> {:cont, {:ok, [encoded | acc]}}
      end
    end)
    |> case do
      {:ok, encoded} -> if parser_after_keep?(encoded), do: :fallback, else: {:ok, Enum.reverse(encoded)}
      other -> other
    end
  end

  # `keep` also narrows which stream labels later parsers must not overwrite;
  # the native parsers keep the original owners, so a parser after it falls back.
  # `encoded` is in reverse order.
  defp parser_after_keep?(encoded) do
    encoded
    |> Enum.reverse()
    |> Enum.drop_while(&(not match?({:keep, _}, &1)))
    |> Enum.any?(&(&1 == :logfmt or match?({:regexp, _}, &1)))
  end

  defp stage(%AST.LineFilter{op: op, value: {:string, s}}) when op in [:contains, :not_contains], do: {op, s}
  defp stage(%AST.LineFilter{op: op, value: {:re, p}}) when op in [:match_re, :not_match_re], do: {op, p}
  defp stage(%AST.LogfmtParser{fields: [], flags: []}), do: :logfmt
  defp stage(%AST.RegexpParser{pattern: pattern}), do: {:regexp, pattern}

  defp stage(%AST.LabelFilter{expr: expr}) do
    case filter(expr) do
      nil -> nil
      encoded -> {:label_filter, encoded}
    end
  end

  defp stage(%AST.Keep{entries: entries}) do
    if Enum.all?(entries, &match?({_, :any}, &1)), do: {:keep, Enum.map(entries, &elem(&1, 0))}
  end

  defp stage(_), do: nil

  defp filter({op, left, right}) when op in [:and, :or] do
    with l when l != nil <- filter(left), r when r != nil <- filter(right), do: {op, l, r}
  end

  defp filter({:cmp, name, op, {:string, value}}) when op in [:eq, :neq], do: {op, name, value}
  defp filter({:cmp, name, op, {:re, pattern}}) when op in [:re, :nre], do: {op, name, StreamMatchers.anchor(pattern)}

  defp filter({:cmp, name, op, {:number, n}}) when op in [:eq, :neq, :lt, :lte, :gt, :gte] and is_number(n),
    do: {:num, op, name, n}

  defp filter(_), do: nil
end
