defmodule Pulse.Test.MetricEvalReference do
  @moduledoc """
  Test-only snapshot of the materializing LogQL metric evaluator replaced by
  streamed evaluation in `Pulse.LogQL.MetricEval`. Parity tests compare both.
  First/last deliberately materialize all selected values before choosing an
  endpoint: the historical snapshot's endpoint-only unwrap validation was a
  shared bug, not an oracle. Literal regression tests pin the corrected contract.
  Missing/empty unwrap fields are independently removed before grouping or
  testing window presence, matching the upstream extractor rather than the
  snapshot's historical extraction error. They also bypass prior pipeline
  errors because no observation reaches the aggregate; the pinned malformed
  JSON quantile HTTP replay retains its original 6 / 5,6 / 6 / empty oracles.
  Failed unwrap conversion replaces earlier pipeline errors before validation,
  as Loki's streamLabelSampleExtractor.Process/LabelsBuilder.SetErr specify.
  Sum-over-time uses compensated summation: the snapshot's plain fold lost
  cancellation residuals. The pinned vector_aggregations.logqltest HTTP replay
  independently retains the original 10/7/17 expectations for this correction.
  Vector sum independently uses compensated summation too: its plain fold
  discarded small contributions across series even after sum-over-time was
  corrected. The pinned TestVectorAggEvaluator_Precision HTTP adaptation keeps
  all 10001 original values and the literal 10000000000010000 oracle.
  Unwrapped-free absence requests the bounded unused-JSON pipeline hint too:
  the historical snapshot unnecessarily parsed malformed lines even when no
  stage needed labels. This is a shared-bug correction, not a reference oracle;
  the five original upstream absence evaluations remain literal HTTP expectations.

  Metric-query evaluator.

  A metric expression is a tree over `RangeAgg`, `VectorAgg`,
  `BinaryOp`, and `NumberLit`. `evaluate/3` walks the tree and produces
  either a `matrix` (a set of time series over the requested steps) or a
  `vector` (one sample per series, at the query's evaluation timestamp).

  Steps and evaluation timestamps come from the caller's `opts`:

    * `start_ts_ns`, `end_ts_ns`, `step_ns` — matrix mode; buckets are
      centered at `start_ts, start_ts + step, ..., end_ts`.
    * `end_ts_ns` alone (no `step_ns`) — vector mode; one sample per
      series at the given timestamp.

  Every range aggregation reads the underlying `%LogQuery{}` via
  `Pulse.LogQL.Evaluator.evaluate_log_raw/3`, so all the same Rust
  pushdown applies. The evaluator groups the returned entries into
  buckets in Elixir and folds the aggregator over each bucket.
  """

  alias Pulse.LogQL.AST
  alias Pulse.LogQL.Entry
  alias Pulse.LogQL.Evaluator
  alias Pulse.LogQL.Quantile
  alias Pulse.PromQL.Evaluator, as: Budget
  alias Pulse.PromQL.FloatParser
  alias Pulse.PromQL.Number
  alias Pulse.PromQL.Operations
  alias Pulse.PromQL.RangeMath

  @default_step_ns 60 * 1_000_000_000
  @max_steps Pulse.QueryLimits.max_evaluation_steps()
  @minimum_timestamp -9_223_372_036_854_775_808

  @over_time_ops [:sum_over_time, :avg_over_time, :max_over_time, :min_over_time, :stddev_over_time, :stdvar_over_time]

  @type result :: {:matrix | :vector, [{map(), term()}]}

  @spec evaluate(term(), Pulse.Storage.tenant(), Evaluator.opts()) :: {:ok, result()} | {:error, term()}
  def evaluate(expr, tenant, opts) when is_binary(tenant) and is_map(opts) do
    if !Process.get(:promql_budget), do: Process.put(:promql_budget, %{samples: 0, work: 0, points: 0, materialized: 0})

    if !Process.get(:promql_deadline_ms),
      do:
        Process.put(:promql_deadline_ms, Process.get(:query_deadline_ms, System.monotonic_time(:millisecond) + 10_000))

    with :ok <- validate_steps(opts),
         {:ok, kind, series} <- eval(expr, tenant, opts) do
      {:ok, {kind, series}}
    end
  catch
    {:promql_error, reason} -> {:error, reason}
    {:logql_error, reason} -> {:error, reason}
  end

  # ---------------------------------------------------------------------------
  # Number literal
  # ---------------------------------------------------------------------------

  defp eval(expr, tenant, opts) do
    Budget.charge(:work, 1)

    with {:ok, kind, series} <- do_eval(expr, tenant, opts) do
      points = Enum.reduce(series, 0, fn item, n -> n + point_count(item, kind) end)
      Budget.charge(:points, points)
      {:ok, kind, series}
    end
  end

  defp do_eval(%type{value: v}, _tenant, opts) when type in [AST.NumberLit, AST.VectorLit] do
    kind = result_kind(opts)

    series =
      case kind do
        :matrix ->
          samples = for ts <- steps(opts), do: {ts, v * 1.0}
          [{%{}, samples}]

        :vector ->
          [{%{}, {evaluation_ts(opts), v * 1.0}}]
      end

    {:ok, kind, series}
  end

  # ---------------------------------------------------------------------------
  # Range aggregation
  # ---------------------------------------------------------------------------

  defp do_eval(%AST.RangeAgg{op: :absent_over_time} = agg, tenant, opts) do
    kind = result_kind(opts)
    times = if kind == :matrix, do: steps(opts), else: [evaluation_ts(opts)]
    offset = agg.offset_ns || 0
    {first, last} = Enum.min_max(times)
    opts = Map.put(opts, :omit_unused_plain_json, is_nil(extract_unwrap(agg.inner)))

    with {:ok, entries} <-
           query_window(remove_unwrap(agg.inner), tenant, opts, first - offset - agg.range_ns + 1, last - offset) do
      unwrap = extract_unwrap(agg.inner)
      entries = observations(entries, unwrap)
      if unwrap, do: Enum.each(entries, &unwrap_value(&1, unwrap, nil))
      points = Enum.flat_map(times, &absence_point(&1, entries, agg.range_ns, offset))
      labels = absence_labels(agg.inner.selector.matchers)
      series = if points == [], do: [], else: [{labels, points}]
      {:ok, kind, result_series(series, kind)}
    end
  end

  defp do_eval(%AST.RangeAgg{} = agg, tenant, opts) do
    kind = result_kind(opts)
    unwrap = extract_unwrap(agg.inner)
    inner_no_unwrap = remove_unwrap(agg.inner)

    case kind do
      :matrix -> run_range_matrix(agg, inner_no_unwrap, unwrap, tenant, opts)
      :vector -> run_range_vector(agg, inner_no_unwrap, unwrap, tenant, opts)
    end
  end

  # ---------------------------------------------------------------------------
  # Vector aggregation
  # ---------------------------------------------------------------------------

  defp do_eval(%AST.VectorAgg{op: op, inner: inner, grouping: g, param: param}, tenant, opts) do
    with {:ok, kind, inner_series} <- eval(inner, tenant, opts) do
      grouped =
        case kind do
          :matrix -> aggregate_matrix(inner_series, op, g, param)
          :vector -> aggregate_vector(inner_series, op, g, param)
        end

      {:ok, kind, grouped}
    end
  end

  # ---------------------------------------------------------------------------
  # Binary operator
  # ---------------------------------------------------------------------------

  defp do_eval(%AST.BinaryOp{op: op, left: l, right: r, bool: bool, matching: matching}, tenant, opts) do
    with {:ok, kind, lser} <- eval(l, tenant, opts),
         {:ok, ^kind, rser} <- eval(r, tenant, opts) do
      times = if kind == :matrix, do: steps(opts), else: [evaluation_ts(opts)]

      series =
        Operations.binary(
          operator(op),
          modifiers(bool, matching),
          normalized(lser, kind),
          normalized(rser, kind),
          expression_type(l),
          expression_type(r),
          times
        )

      result = result_series(series, kind)
      {:ok, kind, result}
    end
  end

  # ---------------------------------------------------------------------------
  # Range helpers
  # ---------------------------------------------------------------------------

  # One storage query for the whole matrix: fetch (min_step - offset - r,
  # max_step - offset] once, then bucket in Elixir per step. Before this
  # refactor a `rate({...}[1h])` at step=15s issued 240 Storage.query
  # calls; now it issues one, at the cost of holding one range's worth of
  # entries in memory for the fold.
  defp run_range_matrix(
         %AST.RangeAgg{op: op, range_ns: r, offset_ns: off, param: p, grouping: grouping},
         inner,
         unwrap,
         tenant,
         opts
       ) do
    step_ts_list = steps(opts)

    if step_ts_list == [] do
      {:ok, :matrix, []}
    else
      spec = %{
        op: op,
        range: r,
        offset: off || 0,
        param: p,
        unwrap: unwrap,
        steps: step_ts_list,
        grouping: grouping
      }

      fetch_and_bucket(spec, inner, tenant, opts)
    end
  end

  defp fetch_and_bucket(spec, inner, tenant, opts) do
    {min_step, max_step} = Enum.min_max(spec.steps)
    union_start = min_step - spec.offset - spec.range + 1
    union_end = max_step - spec.offset

    with {:ok, entries} <- query_window(inner, tenant, opts, union_start, union_end) do
      series =
        entries
        |> observations(spec.unwrap)
        |> Enum.group_by(&entry_label_key(&1, spec.unwrap, spec.grouping))
        |> Enum.map(&bucket_series(&1, spec))
        |> Enum.reject(fn {_, points} -> points == [] end)

      {:ok, :matrix, series}
    end
  end

  defp bucket_series({labels, es}, spec) do
    samples = Enum.flat_map(spec.steps, &bucket_sample(&1, es, spec))
    {labels, samples}
  end

  defp bucket_sample(t, es, spec) do
    bucket_end = t - spec.offset
    bucket_start = bucket_end - spec.range + 1
    bucketed = filter_by_bucket(es, bucket_start, bucket_end)

    if bucketed == [],
      do: [],
      else: [{t, compute_range_agg(spec.op, bucketed, spec.unwrap, bucket_start, bucket_end, spec.param)}]
  end

  defp run_range_vector(
         %AST.RangeAgg{op: op, range_ns: r, offset_ns: off, param: p, grouping: grouping},
         inner,
         unwrap,
         tenant,
         opts
       ) do
    offset = off || 0
    ts = evaluation_ts(opts)
    end_ts = ts - offset
    start_ts = end_ts - r + 1

    with {:ok, entries} <- query_window(inner, tenant, opts, start_ts, end_ts) do
      series =
        entries
        |> observations(unwrap)
        |> Enum.group_by(&entry_label_key(&1, unwrap, grouping))
        |> Enum.map(fn {labels, es} ->
          {labels, {ts, compute_range_agg(op, es, unwrap, start_ts, end_ts, p)}}
        end)

      {:ok, :vector, series}
    end
  end

  defp observations(entries, nil) do
    Enum.each(entries, &check_pipeline_error/1)
    entries
  end

  defp observations(entries, %AST.Unwrap{label: label, conversion: conversion}) do
    entries = Enum.reject(entries, &(Entry.label_value(&1, label) in [nil, ""]))

    Enum.each(entries, fn entry ->
      value = Entry.label_value(entry, label)
      # Invalid present values replace earlier errors with extraction errors,
      # which remain deferred until a window reads that observation. Missing
      # targets were already discarded, independently of prior pipeline errors.
      if parse_unwrap(conversion, value) != nil, do: check_pipeline_error(entry)
    end)

    entries
  end

  defp filter_by_bucket(entries, start_ts, end_ts) do
    Budget.charge(:work, length(entries))

    Enum.filter(entries, fn %Entry{timestamp_ns: ts} ->
      is_integer(ts) and ts >= start_ts and ts <= end_ts
    end)
  end

  # Independent correction to the frozen model: grouping reads ordinary
  # labels, not the rendered authoritative details left after ResetError.
  defp entry_label_key(entry, unwrap, grouping) do
    labels = if is_nil(grouping), do: entry.labels, else: Entry.ordinary_labels(entry)
    labels = if unwrap, do: Map.delete(labels, unwrap.label), else: labels

    case grouping do
      nil -> labels
      %AST.Grouping{mode: :by, labels: names} -> Map.take(labels, names)
      %AST.Grouping{mode: :without, labels: names} -> Map.drop(labels, names)
    end
  end

  defp extract_unwrap(%AST.LogQuery{stages: stages}) do
    Enum.find(stages, &match?(%AST.Unwrap{}, &1))
  end

  defp remove_unwrap(%AST.LogQuery{stages: stages} = q) do
    %{q | stages: Enum.reject(stages, &match?(%AST.Unwrap{}, &1))}
  end

  # `param` is the AST-level scalar argument (currently only
  # `quantile_over_time` uses it). Passing it explicitly avoids the
  # process-dictionary hop that broke on future concurrent evaluation.
  defp compute_range_agg(:count_over_time, entries, _, _, _, _), do: length(entries) * 1.0

  defp compute_range_agg(:rate, entries, unwrap, start_ts, end_ts, _) do
    seconds = (end_ts - start_ts + 1) / 1_000_000_000
    total = if unwrap, do: over_time(:sum_over_time, unwrap_values(entries, unwrap)), else: length(entries) * 1.0
    Number.binary("/", total, seconds)
  end

  defp compute_range_agg(:bytes_over_time, entries, _, _, _, _) do
    entries |> Enum.map(&byte_size(&1.line)) |> Enum.sum() |> Kernel.*(1.0)
  end

  defp compute_range_agg(:bytes_rate, entries, _, start_ts, end_ts, _) do
    seconds = (end_ts - start_ts + 1) / 1_000_000_000
    total = entries |> Enum.map(&byte_size(&1.line)) |> Enum.sum()
    if seconds > 0, do: total / seconds, else: 0.0
  end

  defp compute_range_agg(:first_over_time, entries, unwrap, _, _, _) do
    entries
    |> Enum.sort_by(& &1.timestamp_ns)
    |> Enum.map(&unwrap_value(&1, unwrap, 0.0))
    |> List.first(0.0)
  end

  defp compute_range_agg(:last_over_time, entries, unwrap, _, _, _) do
    entries
    |> Enum.sort_by(& &1.timestamp_ns)
    |> Enum.map(&unwrap_value(&1, unwrap, 0.0))
    |> List.last(0.0)
  end

  defp compute_range_agg(op, entries, unwrap, _start_ts, _end_ts, _) when op in @over_time_ops do
    values = for e <- entries, v = unwrap_value(e, unwrap, nil), v != nil, do: v
    over_time(op, values)
  end

  defp compute_range_agg(:quantile_over_time, entries, unwrap, _, _, param) do
    values = for e <- entries, v = unwrap_value(e, unwrap, nil), v != nil, do: v
    Quantile.calculate(param, values)
  end

  defp absence_point(ts, entries, range, offset) do
    if filter_by_bucket(entries, ts - offset - range + 1, ts - offset) == [], do: [{ts, 1.0}], else: []
  end

  defp absence_labels(matchers) do
    duplicates =
      matchers
      |> Enum.frequencies_by(& &1.name)
      |> Enum.filter(fn {_, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))

    for %AST.Matcher{op: :eq, name: name, value: value} <- matchers,
        name != "__name__" and name not in duplicates,
        into: %{},
        do: {name, value}
  end

  defp unwrap_values(entries, unwrap), do: for(e <- entries, v = unwrap_value(e, unwrap, nil), v != nil, do: v)

  defp over_time(:sum_over_time, values), do: Number.sum(values)
  defp over_time(:avg_over_time, []), do: :nan
  defp over_time(:avg_over_time, values), do: Number.average(values)
  defp over_time(:max_over_time, values), do: Enum.reduce(values, :nan, &Number.max/2)
  defp over_time(:min_over_time, values), do: Enum.reduce(values, :nan, &Number.min/2)
  defp over_time(:stddev_over_time, values), do: stddev(values)
  defp over_time(:stdvar_over_time, values), do: variance(values)

  defp unwrap_value(entry, nil, default), do: length_or_default(entry, default)

  defp unwrap_value(nil, _unwrap, default), do: default

  defp unwrap_value(entry, %AST.Unwrap{label: name, conversion: conv}, _default) do
    with value when is_binary(value) <- Entry.label_value(entry, name),
         number when not is_nil(number) <- parse_unwrap(conv, value) do
      number
    else
      _ -> throw({:logql_error, :sample_extraction_error})
    end
  end

  defp length_or_default(nil, default), do: default
  defp length_or_default(_entry, _default), do: 1.0

  defp parse_unwrap(:none, v) do
    case parse_number_str(v) do
      {:ok, n} -> n
      :error -> nil
    end
  end

  defp parse_unwrap(conv, v) when conv in [:duration, :duration_seconds] do
    case parse_duration(v) do
      {:ok, ns} -> if conv == :duration_seconds, do: ns / 1_000_000_000, else: ns / 1_000_000_000
      :error -> nil
    end
  end

  defp parse_unwrap(:bytes, v) do
    case parse_bytes(v) do
      {:ok, b} -> b * 1.0
      :error -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Vector aggregation
  # ---------------------------------------------------------------------------

  defp aggregate_vector(series, op, grouping, param) do
    series
    |> Enum.group_by(fn {labels, _} -> group_key(labels, grouping) end)
    |> Enum.flat_map(fn {group_labels, group} ->
      values = for {_, {_ts, v}} <- group, do: v
      apply_vector_op(op, group_labels, group, values, param)
    end)
  end

  defp aggregate_matrix(series, op, grouping, param) do
    per_ts =
      Enum.reduce(series, %{}, fn {labels, samples}, acc ->
        Enum.reduce(samples, acc, fn {ts, v}, acc2 ->
          key = {ts, group_key(labels, grouping)}
          Map.update(acc2, key, [{labels, v}], fn existing -> [{labels, v} | existing] end)
        end)
      end)

    result =
      Enum.reduce(per_ts, %{}, fn {{ts, group_labels}, entries}, acc ->
        values = Enum.map(entries, fn {_l, v} -> v end)

        entries_v =
          apply_vector_op_matrix(op, group_labels, entries, values, param)

        Enum.reduce(entries_v, acc, fn {labels, v}, acc2 ->
          Map.update(acc2, labels, [{ts, v}], fn existing -> [{ts, v} | existing] end)
        end)
      end)

    Enum.map(result, fn {labels, samples} ->
      {labels, Enum.sort_by(samples, &elem(&1, 0))}
    end)
  end

  defp apply_vector_op(op, group_labels, group, values, _param)
       when op in [:sum, :avg, :min, :max, :count, :stddev, :stdvar] do
    {_labels, {ts, _value}} = hd(group)
    [{group_labels, {ts, aggregator(op, values)}}]
  end

  defp apply_vector_op(:topk, _group_labels, group, _values, k) when is_integer(k) do
    group
    |> sort_group(:desc, :vector)
    |> Enum.take(max(k, 0))
  end

  defp apply_vector_op(:bottomk, _group_labels, group, _values, k) when is_integer(k) do
    group
    |> sort_group(:asc, :vector)
    |> Enum.take(max(k, 0))
  end

  defp apply_vector_op(:sort, _group_labels, group, _values, _), do: sort_group(group, :asc, :vector)
  defp apply_vector_op(:sort_desc, _group_labels, group, _values, _), do: sort_group(group, :desc, :vector)

  defp apply_vector_op_matrix(op, group_labels, _entries, values, _param)
       when op in [:sum, :avg, :min, :max, :count, :stddev, :stdvar] do
    [{group_labels, aggregator(op, values)}]
  end

  defp apply_vector_op_matrix(:topk, _group_labels, entries, _values, k) when is_integer(k) do
    entries
    |> sort_group(:desc, :matrix)
    |> Enum.take(max(k, 0))
  end

  defp apply_vector_op_matrix(:bottomk, _group_labels, entries, _values, k) when is_integer(k) do
    entries
    |> sort_group(:asc, :matrix)
    |> Enum.take(max(k, 0))
  end

  defp apply_vector_op_matrix(op, _group_labels, entries, _values, _param) when op in [:sort, :sort_desc], do: entries

  defp sort_group(group, direction, kind) do
    Enum.sort(group, fn left, right -> ordered?(sample_value(left, kind), sample_value(right, kind), direction) end)
  end

  defp sample_value({_, {_, value}}, :vector), do: value
  defp sample_value({_, value}, :matrix), do: value
  defp ordered?(:nan, :nan, _), do: true
  defp ordered?(:nan, _, _), do: false
  defp ordered?(_, :nan, _), do: true
  defp ordered?(left, right, :asc), do: not Number.less?(right, left)
  defp ordered?(left, right, :desc), do: not Number.less?(left, right)

  defp aggregator(:sum, values), do: Number.sum(values)
  defp aggregator(:count, values), do: length(values) * 1.0
  defp aggregator(:avg, values), do: over_time(:avg_over_time, values)
  defp aggregator(:min, values), do: over_time(:min_over_time, values)
  defp aggregator(:max, values), do: over_time(:max_over_time, values)
  defp aggregator(:stddev, values), do: stddev(values)
  defp aggregator(:stdvar, values), do: variance(values)

  defp group_key(_labels, nil), do: %{}

  defp group_key(labels, %AST.Grouping{mode: :by, labels: names}) do
    Map.take(labels, names)
  end

  defp group_key(labels, %AST.Grouping{mode: :without, labels: names}) do
    Map.drop(labels, names)
  end

  # ---------------------------------------------------------------------------
  # Binary op helpers
  # ---------------------------------------------------------------------------

  @operators %{
    add: "+",
    sub: "-",
    mul: "*",
    div: "/",
    mod: "%",
    pow: "^",
    eq: "==",
    neq: "!=",
    lt: "<",
    lte: "<=",
    gt: ">",
    gte: ">=",
    and: "and",
    or: "or",
    unless: "unless"
  }
  defp operator(op), do: Map.fetch!(@operators, op)
  defp expression_type(%AST.NumberLit{}), do: :scalar

  defp expression_type(%AST.BinaryOp{left: left, right: right}) do
    if expression_type(left) == :scalar and expression_type(right) == :scalar, do: :scalar, else: :vector
  end

  defp expression_type(_), do: :vector
  defp point_count({_, values}, :matrix), do: length(values)
  defp point_count(_, :vector), do: 1
  defp result_series(series, :matrix), do: series
  defp result_series(series, :vector), do: Enum.map(series, fn {labels, [point]} -> {labels, point} end)
  defp normalized(series, :matrix), do: series
  defp normalized(series, :vector), do: Enum.map(series, fn {labels, point} -> {labels, [point]} end)

  defp modifiers(bool, matching) do
    boolean = if bool, do: ["bool"], else: []
    boolean ++ matching_modifiers(matching)
  end

  defp matching_modifiers(nil), do: []

  defp matching_modifiers(%AST.VectorMatching{mode: mode, labels: labels, group: group, group_labels: included}) do
    match = [[Atom.to_string(mode), labels]]
    if group, do: match ++ [["group_#{group}", included]], else: match
  end

  # ---------------------------------------------------------------------------
  # Bucketing / opts helpers
  # ---------------------------------------------------------------------------

  defp query_window(_inner, _tenant, _opts, _start, finish) when finish < @minimum_timestamp, do: {:ok, []}

  defp query_window(inner, tenant, opts, start, finish) do
    query_opts =
      opts
      |> Map.put(:start_ts_ns, max(start, @minimum_timestamp))
      |> Map.put(:end_ts_ns, finish)
      |> Map.drop([:limit, :direction, :step_ns])

    with {:ok, entries} <- Evaluator.evaluate_log_raw(inner, tenant, query_opts) do
      Budget.charge(:work, length(entries))
      {:ok, entries}
    end
  end

  defp check_pipeline_error(%{labels: %{"__error__" => error}}) when error != "",
    do: throw({:logql_error, :pipeline_error})

  defp check_pipeline_error(_), do: :ok

  defp result_kind(opts) do
    if Map.get(opts, :step_ns), do: :matrix, else: :vector
  end

  defp validate_steps(opts) do
    case Map.get(opts, :step_ns) do
      nil ->
        :ok

      step ->
        validate_step_count(
          Map.get(opts, :start_ts_ns, 0),
          Map.get(opts, :end_ts_ns, Map.get(opts, :start_ts_ns, 0)),
          step
        )
    end
  end

  defp validate_step_count(start, stop, step)
       when is_integer(start) and is_integer(stop) and is_integer(step) and step > 0 and start <= stop do
    if div(stop - start, step) < @max_steps, do: :ok, else: {:error, :invalid_range_or_too_many_steps}
  end

  defp validate_step_count(_start, _stop, _step), do: {:error, :invalid_range_or_too_many_steps}

  defp steps(opts) do
    start = Map.get(opts, :start_ts_ns) || 0
    stop = Map.get(opts, :end_ts_ns) || start
    step = Map.get(opts, :step_ns) || @default_step_ns

    Stream.iterate(start, &(&1 + step))
    |> Stream.take_while(&(&1 <= stop))
    |> Enum.to_list()
  end

  defp evaluation_ts(opts), do: Map.get(opts, :end_ts_ns) || 0

  # ---------------------------------------------------------------------------
  # Numeric helpers
  # ---------------------------------------------------------------------------

  defp parse_number_str(str), do: FloatParser.parse(str)

  defp parse_duration(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, "ns"} -> {:ok, n}
      {n, "us"} -> {:ok, n * 1_000}
      {n, "ms"} -> {:ok, n * 1_000_000}
      {n, "s"} -> {:ok, n * 1_000_000_000}
      {n, "m"} -> {:ok, n * 60 * 1_000_000_000}
      {n, "h"} -> {:ok, n * 3_600 * 1_000_000_000}
      _ -> :error
    end
  end

  @byte_factors %{
    "" => 1,
    "B" => 1,
    "kB" => 1_000,
    "MB" => 1_000_000,
    "GB" => 1_000_000_000,
    "KiB" => 1024,
    "MiB" => 1024 * 1024,
    "GiB" => 1024 * 1024 * 1024
  }

  defp parse_bytes(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, unit} ->
        case Map.get(@byte_factors, unit) do
          nil -> :error
          f -> {:ok, n * f}
        end

      :error ->
        :error
    end
  end

  defp stddev(values), do: RangeMath.deviation(Enum.map(values, &%{value: &1}))
  defp variance(values), do: RangeMath.variance(Enum.map(values, &%{value: &1}))
end
