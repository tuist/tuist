defmodule Pulse.LogQL.MetricEval do
  @moduledoc """
  Metric-query evaluator.

  A metric expression is a tree over `RangeAgg`, `VectorAgg`, `LabelReplace`,
  `BinaryOp`, and literals. `evaluate/3` walks the tree and produces
  a `matrix` (a set of time series over the requested steps), a `vector`
  (one sample per series), or a `scalar` for an instant literal-only tree.

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
  alias Pulse.LogQL.NativeRange
  alias Pulse.LogQL.Pipeline
  alias Pulse.LogQL.Quantile
  alias Pulse.LogQL.Quantity
  alias Pulse.PromQL.Evaluator, as: Budget
  alias Pulse.PromQL.FloatParser
  alias Pulse.PromQL.LabelReplace
  alias Pulse.PromQL.Number
  alias Pulse.PromQL.Operations
  alias Pulse.PromQL.RangeMath
  alias Pulse.Storage.SortOrder

  @default_step_ns 60 * 1_000_000_000
  @max_steps Pulse.QueryLimits.max_evaluation_steps()
  @minimum_timestamp -9_223_372_036_854_775_808

  @over_time_ops [:sum_over_time, :avg_over_time, :max_over_time, :min_over_time, :stddev_over_time, :stdvar_over_time]

  @type result :: {:matrix | :vector | :scalar, [{map(), term()}]}

  @spec evaluate(term(), Pulse.Storage.tenant(), Evaluator.opts()) :: {:ok, result()} | {:error, term()}
  def evaluate(expr, tenant, opts) when is_binary(tenant) and is_map(opts) do
    if !Process.get(:promql_budget),
      do: Process.put(:promql_budget, %{samples: 0, work: 0, points: 0, materialized: 0, log_samples: 0})

    if !Process.get(:promql_deadline_ms),
      do:
        Process.put(:promql_deadline_ms, Process.get(:query_deadline_ms, System.monotonic_time(:millisecond) + 10_000))

    with :ok <- validate_steps(opts),
         :ok <- validate_query_mode(expr, result_kind(opts)),
         {:ok, kind, series} <- eval(expr, tenant, opts) do
      kind = if kind == :vector, do: expression_type(expr), else: kind
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

  # Range aggregations stream the selected entries, reducing each to a
  # compact `{timestamp, tie, value}` sample of its series instead of holding
  # pipeline entries. Every window then reads a slice of the series' samples
  # in the canonical log order. Numeric samples retain no line text; distinct
  # counting retains detached strings under the materialized-sample budget.
  defp do_eval(%AST.RangeAgg{op: :absent_over_time} = agg, tenant, opts) do
    kind = result_kind(opts)
    times = if kind == :matrix, do: steps(opts), else: [evaluation_ts(opts)]
    offset = agg.offset_ns || 0
    {first, last} = Enum.min_max(times)
    spec = %{op: :absent_over_time, unwrap: extract_unwrap(agg.inner), grouping: :all}
    opts = Map.put(opts, :omit_unused_plain_json, is_nil(spec.unwrap))

    with {:ok, collected} <-
           collect(agg.inner, spec, tenant, opts, first - offset - agg.range_ns + 1, last - offset) do
      samples = collected |> Map.values() |> List.flatten() |> ordered()

      points =
        for t <- times, window(samples, t - offset - agg.range_ns + 1, t - offset) == :empty, do: {t, 1.0}

      labels = absence_labels(agg.inner.selector.matchers)
      series = if points == [], do: [], else: [{labels, points}]
      {:ok, kind, result_series(series, kind)}
    end
  end

  defp do_eval(%AST.RangeAgg{op: op, range_ns: range, offset_ns: offset, param: param} = agg, tenant, opts) do
    kind = result_kind(opts)
    offset = offset || 0
    times = if kind == :matrix, do: steps(opts), else: [evaluation_ts(opts)]

    spec = %{
      op: op,
      param: param,
      unwrap: extract_unwrap(agg.inner),
      grouping: agg.grouping,
      binnable: minute_windows?(times, range, offset)
    }

    if times == [] do
      {:ok, kind, []}
    else
      {first, last} = Enum.min_max(times)

      with {:ok, collected} <-
             collect(agg.inner, spec, tenant, opts, first - offset - range + 1, last - offset) do
        {:ok, kind, Enum.flat_map(collected, &series_points(&1, times, spec, range, offset, kind))}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Vector aggregation
  # ---------------------------------------------------------------------------

  # Exact ranking is the bounded implementation here, not a count-min sketch.
  # All input samples and intermediate points still spend the ordinary budgets.
  defp do_eval(%AST.VectorAgg{op: :approx_topk} = agg, tenant, opts), do: do_eval(%{agg | op: :topk}, tenant, opts)

  # A sum of line or byte counts groups while counting: integer sums are
  # exact in any order, and the inner series key is the outer group's. One
  # series per group instead of per stream (or, after a parser, per distinct
  # parsed label set) keeps volume panels over thousands of streams and
  # parsed-field alerts over high-cardinality fields within the point and
  # heap budgets. A pipeline qualifies while every kept line with an error
  # label still fails the query (no explicit error selection) and no stage
  # can rename or remove error labels; grouping by an error label does not.
  # Rates stay per stream: dividing before or after summing can differ in the
  # last bit.
  defp do_eval(
         %AST.VectorAgg{
           op: :sum,
           grouping: g,
           inner: %AST.RangeAgg{op: op, grouping: nil, inner: %AST.LogQuery{stages: stages}} = range
         } = agg,
         tenant,
         opts
       )
       when op in [:count_over_time, :bytes_over_time] do
    if groupable?(stages, g) do
      # The inner grouping is no longer nil, so this reaches the general sum.
      do_eval(%{agg | inner: %{range | grouping: g || %AST.Grouping{mode: :by, labels: []}}}, tenant, opts)
    else
      vector_agg(agg, tenant, opts)
    end
  end

  defp do_eval(%AST.VectorAgg{} = agg, tenant, opts), do: vector_agg(agg, tenant, opts)

  defp do_eval(%AST.LabelReplace{} = expr, tenant, opts) do
    with {:ok, kind, series} <- eval(expr.inner, tenant, opts) do
      # Loki's dot does not match newlines by default. Reuse capture expansion
      # directly, without PromQL's output coalescing or dot-all default.
      args =
        for value <- [expr.dst, expr.replacement, expr.src, Pulse.QueryRegex.non_dotall(expr.regex)],
            do: {:string, value}

      {:ok, kind, LabelReplace.run(series, args)}
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
          binary_denominator(normalized(rser, kind), op),
          expression_type(l),
          expression_type(r),
          times
        )

      result = result_series(series, kind)
      {:ok, kind, result}
    end
  end

  defp vector_agg(%AST.VectorAgg{op: op, inner: inner, grouping: g, param: param}, tenant, opts) do
    with {:ok, kind, inner_series} <- eval(inner, tenant, opts) do
      grouped =
        case kind do
          :matrix -> aggregate_matrix(inner_series, op, g, param)
          :vector -> aggregate_vector(inner_series, op, g, param)
        end

      {:ok, kind, grouped}
    end
  end

  @groupable_stages [
    AST.LineFilter,
    AST.LogfmtParser,
    AST.JsonParser,
    AST.RegexpParser,
    AST.PatternParser,
    AST.UnpackParser,
    AST.LabelFilter,
    AST.LineFormat,
    AST.Decolorize
  ]

  defp groupable?(stages, grouping) do
    labels = if grouping, do: grouping.labels, else: []

    Enum.all?(stages, &(&1.__struct__ in @groupable_stages)) and not Pipeline.preserves_errors?(stages) and
      not Enum.any?(labels, &(&1 in ["__error__", "__error_details__"]))
  end

  # Loki defines division by either signed zero as NaN, unlike PromQL's
  # signed infinities. Adapt only the LogQL denominator before shared math.
  defp binary_denominator(series, :div) do
    Enum.map(series, fn {labels, points} ->
      Budget.charge(:work, length(points))
      {labels, Enum.map(points, fn {ts, value} -> {ts, if(value == 0, do: :nan, else: value)} end)}
    end)
  end

  defp binary_denominator(series, _op), do: series

  # ---------------------------------------------------------------------------
  # Range helpers
  # ---------------------------------------------------------------------------

  defp entry_label_key(entry, unwrap, grouping) do
    labels = if is_nil(grouping), do: entry.labels, else: Entry.ordinary_labels(entry)
    labels = if unwrap, do: Map.delete(labels, unwrap.label), else: labels

    grouped =
      case grouping do
        nil -> labels
        %AST.Grouping{mode: :by, labels: names} -> Map.take(labels, names)
        %AST.Grouping{mode: :without, labels: names} -> Map.drop(labels, names)
      end

    Entry.preserve_error_labels(entry, grouped)
  end

  defp extract_unwrap(%AST.LogQuery{stages: stages}) do
    Enum.find(stages, &match?(%AST.Unwrap{}, &1))
  end

  defp extraction(%AST.LogQuery{stages: stages} = query, spec) do
    {before, rest} = Enum.split_while(stages, &(not match?(%AST.Unwrap{}, &1)))
    after_unwrap = if rest == [], do: [], else: tl(rest)

    spec =
      Map.merge(spec, %{
        post_filter: Pipeline.compile(after_unwrap),
        preserve_errors: Pipeline.preserves_errors?(stages)
      })

    {%{query | stages: before}, spec}
  end

  # ---------------------------------------------------------------------------
  # Streamed samples
  # ---------------------------------------------------------------------------

  # Every entry in (start, finish] becomes one sample of its series. A
  # pipeline error fails the query wherever it occurs, as before; an unwrap
  # failure is kept as `:error` and fails only a window that reads it.
  defp collect(_inner, _spec, _tenant, _opts, _start, finish) when finish < @minimum_timestamp, do: {:ok, %{}}

  defp collect(inner, spec, tenant, opts, start, finish) do
    {inner, spec} = extraction(inner, spec)

    query_opts =
      opts
      |> Map.put(:start_ts_ns, max(start, @minimum_timestamp))
      |> Map.put(:end_ts_ns, finish)
      |> Map.drop([:limit, :direction, :step_ns])

    case NativeRange.collect(inner, spec, tenant, query_opts) do
      :fallback -> collect_entries(inner, spec, tenant, query_opts)
      result -> result
    end
  end

  defp collect_entries(inner, spec, tenant, query_opts) do
    Evaluator.fold_log(inner, tenant, query_opts, %{}, &add_entry(&1, &2, &3, spec))
  end

  defp add_entry(entry, _record, acc, %{op: :approx_count_distinct, param: name} = spec) do
    check_pipeline_error(entry, spec)

    case {entry.timestamp_ns, Entry.label_value(entry, name)} do
      {ts, value} when is_integer(ts) and is_binary(value) and value != "" ->
        Budget.charge(:log_samples, 1)
        Budget.charge(:materialized, 1)
        add_sample(acc, series_key(entry, spec), {ts, nil, :binary.copy(value)})

      _ ->
        acc
    end
  end

  # A missing/empty unwrap field supplies no observation, unlike a present
  # nonnumeric field. The fold still charges all scanned/pipeline rows as work.
  # Earlier pipeline errors cannot reach the aggregate without an observation.
  defp add_entry(entry, record, acc, spec) do
    if spec.unwrap && Entry.label_value(entry, spec.unwrap.label) in [nil, ""] do
      acc
    else
      case extract_sample(entry, spec) do
        {:keep, %Entry{timestamp_ns: ts} = entry, value} when is_integer(ts) ->
          Budget.charge(:log_samples, 1)
          add_sample(acc, series_key(entry, spec), {ts, tie(spec.op, record), value})

        _ ->
          acc
      end
    end
  end

  defp extract_sample(entry, %{unwrap: nil} = spec) do
    check_pipeline_error(entry, spec)
    {:keep, entry, entry_value(spec, entry)}
  end

  defp extract_sample(entry, spec) do
    {value, filtered_entry} = unwrapped(entry, spec.unwrap)

    case Pipeline.apply(spec.post_filter, filtered_entry) do
      {:keep, filtered_entry} ->
        if value != :error, do: check_pipeline_error(filtered_entry, spec)
        value = if value == :error and spec.preserve_errors, do: 0.0, else: value
        if value == :error and spec.op == :absent_over_time, do: throw({:logql_error, :sample_extraction_error})
        {:keep, filtered_entry, value}

      :drop ->
        :drop
    end
  end

  defp extraction_error(entry, %{label: name, conversion: conversion}) do
    {:ok, value} = Entry.fetch_label(entry, name)

    details =
      case conversion do
        :none -> "strconv.ParseFloat: parsing #{Pulse.JSON.encode!(value)}: invalid syntax"
        _ -> "cannot convert #{Pulse.JSON.encode!(value)} with #{conversion}"
      end

    extraction_error(entry, details)
  end

  defp extraction_error(entry, details) when is_binary(details),
    do: Entry.set_error(entry, "SampleExtractionErr", details)

  defp add_sample(acc, key, sample) do
    case acc do
      %{^key => samples} -> %{acc | key => [sample | samples]}
      # Labels can be slices of a decoded chunk; copy the first so a series
      # never keeps its chunk alive.
      _ -> Map.put(acc, :erlang.binary_to_term(:erlang.term_to_binary(key)), [sample])
    end
  end

  defp series_key(_entry, %{grouping: :all}), do: %{}

  defp series_key(entry, %{op: :approx_count_distinct, param: name, grouping: grouping}),
    do: entry_label_key(%{entry | labels: Map.delete(entry.labels, name)}, nil, grouping)

  defp series_key(entry, %{unwrap: unwrap, grouping: grouping}), do: entry_label_key(entry, unwrap, grouping)

  # Equal timestamps keep the complete record key where ordering decides the
  # result (first/last or counter resets); detach it from segment memory.
  defp tie(op, record) when op in [:first_over_time, :last_over_time, :rate_counter],
    do: record |> SortOrder.log_key() |> :erlang.term_to_binary() |> :erlang.binary_to_term()

  defp tie(_op, _record), do: nil

  defp entry_value(%{op: op}, entry) when op in [:bytes_over_time, :bytes_rate], do: byte_size(entry.line)
  defp entry_value(%{op: :count_over_time}, _entry), do: 1.0
  defp entry_value(%{unwrap: nil}, _entry), do: 1.0

  defp unwrapped(entry, %AST.Unwrap{label: name, conversion: conv} = unwrap) do
    with value when is_binary(value) <- Entry.label_value(entry, name),
         number when not is_nil(number) <- parse_unwrap(conv, value) do
      case number do
        {:error, details} -> {:error, extraction_error(entry, details)}
        value -> {value, entry}
      end
    else
      _ -> {:error, extraction_error(entry, unwrap)}
    end
  end

  # Descending timestamp, then the canonical tie: the order a materialized,
  # sorted result presents entries in. Windows are contiguous slices.
  # Samples are a tuple of `{ts, tie, value}` (Elixir pipeline) or native
  # `{:packed, binary}` of `<<ts::64, tag::8, value::64>>` records, which stay
  # off the process heap: windows decode only the slice they read.
  # `{:binned, binary}` packs the same records, one per minute bucket end
  # with an integer count or byte total (`Pulse.LogQL.NativeRange`).
  defp ordered({kind, _} = packed) when kind in [:packed, :binned], do: packed
  defp ordered(samples), do: samples |> Enum.sort(:desc) |> List.to_tuple()

  defp size({kind, binary}) when kind in [:packed, :binned], do: div(byte_size(binary), 17)
  defp size(samples), do: tuple_size(samples)

  defp ts_at({kind, binary}, i) when kind in [:packed, :binned] do
    <<ts::signed-64>> = binary_part(binary, i * 17, 8)
    ts
  end

  defp ts_at(samples, i), do: elem(elem(samples, i), 0)

  defp value_at({kind, binary}, i) when kind in [:packed, :binned] do
    case binary_part(binary, i * 17 + 8, 9) do
      <<0, value::float-64>> -> value
      <<1, _::binary>> -> :error
      <<2, value::signed-64>> -> value
    end
  end

  defp value_at(samples, i), do: elem(elem(samples, i), 2)

  defp window(samples, start, finish) do
    first = search(samples, &(&1 <= finish))
    last = search(samples, &(&1 < start)) - 1
    if first > last, do: :empty, else: {first, last}
  end

  # First index whose timestamp satisfies a predicate monotone in the order.
  defp search(samples, predicate), do: search(samples, predicate, 0, size(samples))
  defp search(_samples, _predicate, low, high) when low >= high, do: low

  defp search(samples, predicate, low, high) do
    middle = div(low + high, 2)

    if predicate.(ts_at(samples, middle)),
      do: search(samples, predicate, low, middle),
      else: search(samples, predicate, middle + 1, high)
  end

  defp window_point(t, samples, spec, range, offset) do
    finish = t - offset
    start = finish - range + 1

    case window(samples, start, finish) do
      :empty ->
        nil

      {first, last} ->
        Budget.charge(:work, last - first + 1)
        {t, aggregate(spec, samples, first, last, start, finish)}
    end
  end

  defp series_points({labels, samples}, times, spec, range, offset, kind) do
    samples = ordered(samples)
    points = for t <- times, point = window_point(t, samples, spec, range, offset), point != nil, do: point
    range_series(labels, points, kind)
  end

  defp range_series(_labels, [], _kind), do: []
  defp range_series(labels, points, :matrix), do: [{labels, points}]
  defp range_series(labels, [point], :vector), do: [{labels, point}]

  # Binned windows sum their buckets' line counts or bytes; the results equal
  # the per-line folds below.
  defp aggregate(%{op: op}, {:binned, _} = samples, first, last, _start, _finish)
       when op in [:count_over_time, :bytes_over_time], do: samples |> slice(first, last) |> Enum.sum() |> Kernel.*(1.0)

  defp aggregate(%{op: :rate}, {:binned, _} = samples, first, last, start, finish),
    do: Number.binary("/", Enum.sum(slice(samples, first, last)) * 1.0, (finish - start + 1) / 1_000_000_000)

  defp aggregate(%{op: :bytes_rate}, {:binned, _} = samples, first, last, start, finish) do
    seconds = (finish - start + 1) / 1_000_000_000
    total = samples |> slice(first, last) |> Enum.sum()
    if seconds > 0, do: total / seconds, else: 0.0
  end

  defp aggregate(%{op: :count_over_time}, _samples, first, last, _start, _finish), do: (last - first + 1) * 1.0

  # Exact string identity, not a probabilistic sketch or a sum of per-stream
  # cardinalities. Each window visit already spends the ordinary work budget.
  defp aggregate(%{op: :approx_count_distinct}, samples, first, last, _start, _finish) do
    first..last//1
    |> Enum.reduce(MapSet.new(), fn index, distinct -> MapSet.put(distinct, value_at(samples, index)) end)
    |> MapSet.size()
    |> Kernel.*(1.0)
  end

  defp aggregate(%{op: :rate, unwrap: unwrap}, samples, first, last, start, finish) do
    seconds = (finish - start + 1) / 1_000_000_000
    total = if unwrap, do: over_time(:sum_over_time, values!(samples, first, last)), else: (last - first + 1) * 1.0
    Number.binary("/", total, seconds)
  end

  defp aggregate(%{op: :rate_counter}, samples, first, last, start, finish) do
    initial = checked(samples, last)
    difference = Number.binary("-", checked(samples, first), initial)

    # Walk forward in source time, including every reset rather than only the
    # endpoints. Equal-time observations follow ascending canonical record keys.
    {increase, _previous} =
      Enum.reduce(last..first//-1, {difference, 0.0}, fn index, {increase, previous} ->
        value = checked(samples, index)
        increase = if Number.compare("<", value, previous), do: Number.add(increase, previous), else: increase
        {increase, value}
      end)

    if first == last do
      0.0
    else
      elapsed = (ts_at(samples, first) - ts_at(samples, last)) / 1_000_000_000
      spacing = elapsed / (last - first)
      left = (ts_at(samples, last) - start + 1) / 1_000_000_000
      right = (finish - ts_at(samples, first)) / 1_000_000_000
      left = if left >= spacing * 1.1, do: spacing / 2, else: left
      right = if right >= spacing * 1.1, do: spacing / 2, else: right

      # Cap by sample spacing before the counter's zero point. Reversing these
      # caps can incorrectly extend a sparse counter's extrapolation.
      left =
        if Number.compare(">", increase, 0) and Number.compare(">=", initial, 0),
          do: Number.min(left, Number.multiply(elapsed, Number.divide(initial, increase))),
          else: left

      factor = Number.divide(elapsed + left + right, elapsed)
      Number.divide(Number.multiply(increase, factor), (finish - start + 1) / 1_000_000_000)
    end
  end

  defp aggregate(%{op: :bytes_over_time}, samples, first, last, _start, _finish),
    do: samples |> slice(first, last) |> Enum.sum() |> Kernel.*(1.0)

  defp aggregate(%{op: :bytes_rate}, samples, first, last, start, finish) do
    seconds = (finish - start + 1) / 1_000_000_000
    total = samples |> slice(first, last) |> Enum.sum()
    if seconds > 0, do: total / seconds, else: 0.0
  end

  # Ascending by time, first keeps the earliest timestamp's first entry in
  # canonical order and last keeps the latest timestamp's last entry.
  defp aggregate(%{op: :first_over_time}, samples, first, last, _start, _finish) do
    validate_window!(samples, first, last)
    earliest = ts_at(samples, last)
    index = search(samples, &(&1 <= earliest))
    checked(samples, max(index, first))
  end

  defp aggregate(%{op: :last_over_time}, samples, first, last, _start, _finish) do
    validate_window!(samples, first, last)
    latest = ts_at(samples, first)
    index = search(samples, &(&1 < latest)) - 1
    checked(samples, min(index, last))
  end

  defp aggregate(%{op: op}, samples, first, last, _start, _finish) when op in @over_time_ops,
    do: over_time(op, values!(samples, first, last))

  defp aggregate(%{op: :quantile_over_time, param: param}, samples, first, last, _start, _finish),
    do: Quantile.calculate(param, values!(samples, first, last))

  defp slice(samples, first, last), do: for(i <- first..last//1, do: value_at(samples, i))

  defp values!(samples, first, last) do
    values = slice(samples, first, last)
    if Enum.member?(values, :error), do: throw({:logql_error, :sample_extraction_error}), else: values
  end

  # First/last need no materialized values list, but every selected sample in
  # this window must validate. Gaps between sparse evaluation windows do not.
  defp validate_window!(samples, first, last) do
    Enum.each(first..last, &checked(samples, &1))
  end

  defp checked(samples, index) do
    case value_at(samples, index) do
      :error -> throw({:logql_error, :sample_extraction_error})
      value -> value
    end
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

  defp over_time(:sum_over_time, values), do: Number.sum(values)
  defp over_time(:avg_over_time, []), do: :nan
  defp over_time(:avg_over_time, values), do: Number.average(values)
  defp over_time(:max_over_time, values), do: Enum.reduce(values, :nan, &Number.max/2)
  defp over_time(:min_over_time, values), do: Enum.reduce(values, :nan, &Number.min/2)
  defp over_time(:stddev_over_time, values), do: stddev(values)
  defp over_time(:stdvar_over_time, values), do: variance(values)

  defp parse_unwrap(:none, v) do
    case parse_number_str(v) do
      {:ok, n} -> n
      {:error, _details} = error -> error
      :error -> nil
    end
  end

  defp parse_unwrap(conv, v) when conv in [:duration, :duration_seconds] do
    case parse_duration(v) do
      {:ok, ns} -> div(ns, 1_000_000_000) + rem(ns, 1_000_000_000) / 1_000_000_000
      {:error, _details} = error -> error
      :error -> nil
    end
  end

  defp parse_unwrap(:bytes, v) do
    case parse_bytes(v) do
      {:ok, b} -> b * 1.0
      {:error, _details} = error -> error
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

  defp check_pipeline_error(_entry, %{preserve_errors: true}), do: :ok

  # Admission of samples still guards the rendered error label, just as Loki's
  # pipelineErr checks sample labels rather than the builder's private error.
  defp check_pipeline_error(%{labels: %{"__error__" => error}}, _spec) when error != "",
    do: throw({:logql_error, :pipeline_error})

  defp check_pipeline_error(_, _), do: :ok

  defp result_kind(opts) do
    if Map.get(opts, :step_ns), do: :matrix, else: :vector
  end

  # Inspect the whole tree before a left-hand selector can start storage work.
  defp validate_query_mode(_expr, :vector), do: :ok
  defp validate_query_mode(%AST.VectorAgg{op: :approx_topk}, :matrix), do: {:error, :instant_query_required}
  defp validate_query_mode(%AST.VectorAgg{inner: inner}, kind), do: validate_query_mode(inner, kind)
  defp validate_query_mode(%AST.LabelReplace{inner: inner}, kind), do: validate_query_mode(inner, kind)

  defp validate_query_mode(%AST.BinaryOp{left: left, right: right}, kind) do
    with :ok <- validate_query_mode(left, kind), do: validate_query_mode(right, kind)
  end

  defp validate_query_mode(_expr, _kind), do: :ok

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

  # Every window `(t - offset - range, t - offset]` is a run of whole minute
  # buckets, so per-minute counts answer it exactly.
  @minute_ns 60_000_000_000
  defp minute_windows?(times, range, offset),
    do: rem(range, @minute_ns) == 0 and range > 0 and Enum.all?(times, &(rem(&1 - offset, @minute_ns) == 0))

  # ---------------------------------------------------------------------------
  # Numeric helpers
  # ---------------------------------------------------------------------------

  defp parse_number_str(str), do: FloatParser.parse_with_error(str)

  defp parse_duration(str), do: Quantity.duration_value(str)
  defp parse_bytes(str), do: Quantity.bytes_value(str)

  defp stddev(values), do: RangeMath.deviation(Enum.map(values, &%{value: &1}))
  defp variance(values), do: RangeMath.variance(Enum.map(values, &%{value: &1}))
end
