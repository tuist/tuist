defmodule Pulse.Traces.Metrics do
  @moduledoc """
  TraceQL metrics queries (Tempo's `/api/metrics/query_range` and
  `/api/metrics/query`), which Grafana's Traces Drilldown and Tempo metrics
  panels use.

  A query is a span selector piped into one first-stage function:

      {<selector>} | rate() | count_over_time()
                   | min_over_time(<attr>) | max_over_time(<attr>)
                   | sum_over_time(<attr>) | avg_over_time(<attr>)
                   | quantile_over_time(<attr>, <q>, ...)
                   | histogram_over_time(<attr>)
                   [by (<attr>, ...)] [with (...)]

  The selector is `{}`, `{true}`, or the bounded boolean grammar of
  `Pulse.Traces.SearchExpression`, optionally `&&`-combined with `true` and
  `nestedSetParent<0` (root spans only). `<attr>` is `duration`,
  `span.<key>`, `resource.<key>` or `.<key>`; `by` also accepts `name`,
  `status`, `kind` and `span:id`, and at most five attributes. `with (...)` hints are
  accepted and ignored, so sampling hints yield exact results.

  Parenthesized pipelines compose with `+`, `-`, `*`, `/` and scalar constants.
  Scalar-right comparisons filter values; all branches share one storage scan
  and native series/point/work budgets. Arithmetic runs in the bounded query
  worker after native aggregation. A single scalar filter may also precede
  `topk`/`bottomk` on a pipeline; that filter runs natively before ranking.

  Spans are reduced natively per segment (`trace_metrics.rs`); see that
  module for the interval, labeling and quantile semantics.
  """

  alias Pulse.Codec.NIF
  alias Pulse.QueryRunner
  alias Pulse.Storage
  alias Pulse.Traces.MetricExpression
  alias Pulse.Traces.SearchExpression

  @functions ~w(rate count_over_time min_over_time max_over_time sum_over_time avg_over_time quantile_over_time histogram_over_time)
  @attribute ~r/\A(?:(span|resource)\.([A-Za-z_][A-Za-z0-9_.\-]*)|\.([A-Za-z_][A-Za-z0-9_.\-]*)|(?:span:)?(duration|name|status|kind))\z/

  @type query :: pipeline() | %{expression: tuple(), leaves: [pipeline()]}
  @type pipeline :: %{
          program: list() | nil,
          root_only: boolean(),
          op: String.t(),
          quantiles: [float()],
          value: {String.t(), String.t()} | nil,
          by: [{String.t(), String.t(), String.t()}],
          second: {String.t(), pos_integer()} | {String.t(), pos_integer(), {String.t(), float()}} | nil
        }

  @doc """
  Evaluate `query` over `{start_ns, end_ns, step_ns}`; `instant` selects
  Tempo's instant response. Range windows are aligned to the step as Tempo
  aligns them, with one extra leading interval.
  """
  @spec query(String.t(), String.t(), {integer(), integer(), pos_integer() | nil}, boolean()) ::
          {:ok, binary()} | {:error, term()}
  def query(tenant, text, window, instant) do
    with {:ok, parsed} <- parse(text),
         {:ok, window} <- window(window, instant) do
      QueryRunner.run(tenant, :raw, fn deadline ->
        run(tenant, parsed, window, QueryRunner.storage_opts(deadline))
      end)
    end
  end

  # A source removed mid-scan (compaction, retention) leaves a partial
  # accumulator; the scan restarts once against the current sources.
  defp run(tenant, parsed, window, storage_opts, attempts \\ 2) do
    {start, finish, _step, _instant} = window
    opts = Keyword.merge(storage_opts, start_ts: start, end_ts: finish)
    # The selector lets storage skip sources no matching span can be in.
    opts = if is_list(parsed[:program]), do: Keyword.put(opts, :trace_program, parsed.program), else: opts

    with {:ok, metrics} <- new(parsed, window) do
      case Storage.trace_metrics_scan(tenant, opts, metrics) do
        {:ok, _rows} ->
          finish(parsed, metrics, window)

        {:error, :native_fallback} when attempts > 1 and not is_map_key(parsed, :expression) ->
          run(tenant, parsed, window, storage_opts, attempts - 1)

        {:error, :native_fallback} ->
          {:error, :query_execution_failed}

        {:error, _} = error ->
          error
      end
    end
  end

  defp new(%{leaves: leaves}, window) do
    leaves
    |> Enum.reduce_while({:ok, []}, fn leaf, {:ok, resources} ->
      case new(leaf, window) do
        {:ok, resource} -> {:cont, {:ok, [resource | resources]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, resources} -> native(NIF.trace_metrics_batch_new(Enum.reverse(resources)))
      error -> error
    end
  end

  defp new(parsed, window) do
    native(
      NIF.trace_metrics_new(
        parsed.program,
        parsed.root_only,
        parsed.op,
        parsed.quantiles,
        parsed.value,
        parsed.by,
        window,
        parsed.second
      )
    )
  end

  defp finish(%{expression: _} = parsed, metrics, window) do
    with {:ok, leaves} <- native(NIF.trace_metrics_batch_finish(metrics)),
         do: MetricExpression.finish(parsed, leaves, window)
  end

  defp finish(_parsed, metrics, _window), do: native(NIF.trace_metrics_finish(metrics))

  defp native(:fallback), do: {:error, :unsupported_trace_selector}
  defp native(result), do: result

  # -- windows ------------------------------------------------------------------

  defguardp valid_bounds(start, finish)
            when is_integer(start) and is_integer(finish) and start >= 0 and finish > start and
                   finish <= 9_223_372_036_854_775_807

  defguardp valid_step(step) when is_nil(step) or (is_integer(step) and step > 0)

  @doc false
  def window({start, finish, _step}, true) when valid_bounds(start, finish),
    do: {:ok, {start, finish, finish - start, true}}

  def window({start, finish, step}, false) when valid_bounds(start, finish) and valid_step(step) do
    step = step || default_step(start, finish)
    aligned_start = start - rem(start, step)
    aligned_end = if rem(finish, step) == 0, do: finish, else: finish + step - rem(finish, step)
    aligned_start = if aligned_start > step, do: aligned_start - step, else: aligned_start

    # Tempo checks the requested range before alignment adds boundary intervals.
    cond do
      div(finish - start, step) > 10_000 ->
        {:error, {:trace_metrics_step_too_small, step, div(finish - start, 10_000)}}

      aligned_end <= 9_223_372_036_854_775_807 and div(aligned_end - aligned_start, step) in 1..11_000 ->
        {:ok, {aligned_start, aligned_end, step, false}}

      true ->
        {:error, :unsupported_parameters}
    end
  end

  def window(_window, _instant), do: {:error, :unsupported_parameters}

  # Target 240 points, rounding down at Tempo's window-dependent granularity.
  @doc false
  def default_step(start, finish) do
    baseline = div(finish - start, 240)

    granularity =
      if finish - start < 60_000_000_000 do
        50_000_000
      else
        Enum.find([3600, 300, 60, 15, 5, 1], 1, &(&1 * 1_000_000_000 <= baseline)) * 1_000_000_000
      end

    max(div(baseline, granularity), 1) * granularity
  end

  # -- parsing ------------------------------------------------------------------

  @doc "Parse a TraceQL metrics query."
  @spec parse(String.t()) :: {:ok, query()} | {:error, term()}
  def parse(text) when is_binary(text) and byte_size(text) <= 16_384 do
    if String.valid?(text),
      do: MetricExpression.parse(text, &parse_pipeline/1),
      else: {:error, :unsupported_trace_selector}
  end

  def parse(_text), do: {:error, :query_expression_limit}

  defp parse_pipeline(text) do
    with {:ok, selector, rest} <- split_selector(String.trim(text)),
         {:ok, program, root_only} <- selector(selector),
         {:ok, op, args, by, second} <- pipeline(rest),
         {:ok, value, quantiles} <- arguments(op, args),
         {:ok, by} <- group_by(by) do
      {:ok,
       %{program: program, root_only: root_only, op: op, quantiles: quantiles, value: value, by: by, second: second}}
    else
      {:error, _} = error -> error
      _ -> {:error, :unsupported_trace_selector}
    end
  end

  defp split_selector("{" <> _ = text) do
    case closing(text, 0, 0, false) do
      nil -> :error
      at -> {:ok, binary_part(text, 1, at - 1), binary_part(text, at + 1, byte_size(text) - at - 1)}
    end
  end

  defp split_selector(_text), do: :error

  # Index of the brace closing the selector, skipping quoted strings.
  defp closing(text, i, depth, quoted) when i < byte_size(text) do
    case {:binary.at(text, i), quoted} do
      {?\\, true} -> closing(text, i + 2, depth, true)
      {?", q} -> closing(text, i + 1, depth, not q)
      {_, true} -> closing(text, i + 1, depth, true)
      {?{, false} -> closing(text, i + 1, depth + 1, false)
      {?}, false} when depth == 1 -> i
      {?}, false} -> closing(text, i + 1, depth - 1, false)
      _ -> closing(text, i + 1, depth, false)
    end
  end

  defp closing(_text, _i, _depth, _quoted), do: nil

  # `true` and `nestedSetParent<0` (root spans) may be `&&`-combined with a
  # bounded expression. `&&` and `||` share one precedence, so the selector is
  # only split on `&&` when it has no top-level `||`.
  defp selector(inner) do
    {terms, has_or} = top_level(inner)
    terms = Enum.map(terms, &String.trim/1)
    special? = &(String.replace(&1, ~r/\s+/, "") in ["true", "nestedSetParent<0", "span:nestedSetParent<0"])

    cond do
      String.trim(inner) == "" ->
        {:ok, nil, false}

      has_or and Enum.any?(terms, special?) ->
        {:error, :unsupported_trace_selector}

      has_or ->
        expression(inner, false)

      true ->
        {special, rest} = Enum.split_with(terms, special?)
        root_only = Enum.any?(special, &String.contains?(&1, "nestedSetParent"))
        if rest == [], do: {:ok, nil, root_only}, else: expression(Enum.join(rest, " && "), root_only)
    end
  end

  defp expression(text, root_only) do
    case SearchExpression.parse("{" <> text <> "}") do
      {:ok, {:expression, program}} -> {:ok, program, root_only}
      {:error, _} = error -> error
    end
  end

  # The selector split at top-level `&&`, and whether it has a top-level `||`.
  defp top_level(text), do: top_level(text, 0, false, "", [], false)

  defp top_level(<<>>, _depth, _quoted, current, terms, has_or), do: {Enum.reverse([current | terms]), has_or}

  defp top_level(<<"\\", c::utf8, rest::binary>>, depth, true, current, terms, has_or),
    do: top_level(rest, depth, true, current <> <<?\\, c::utf8>>, terms, has_or)

  defp top_level(<<?", rest::binary>>, depth, quoted, current, terms, has_or),
    do: top_level(rest, depth, not quoted, current <> "\"", terms, has_or)

  defp top_level(<<c::utf8, rest::binary>>, depth, true, current, terms, has_or),
    do: top_level(rest, depth, true, current <> <<c::utf8>>, terms, has_or)

  defp top_level(<<"&&", rest::binary>>, 0, false, current, terms, has_or),
    do: top_level(rest, 0, false, "", [current | terms], has_or)

  defp top_level(<<"||", rest::binary>>, 0, false, current, terms, _has_or),
    do: top_level(rest, 0, false, current <> "||", terms, true)

  defp top_level(<<c::utf8, rest::binary>>, depth, false, current, terms, has_or) do
    depth = depth + if(c == ?(, do: 1, else: 0) - if(c == ?), do: 1, else: 0)
    top_level(rest, depth, false, current <> <<c::utf8>>, terms, has_or)
  end

  defp pipeline(rest) do
    rest = rest |> String.trim() |> strip_hints()

    with "|" <> call <- rest,
         [_, op, args, tail] <- Regex.run(~r/\A\s*([a-z_]+)\s*\(([^()]*)\)(.*)\z/s, call),
         true <- op in @functions,
         {tail, second} = second_stage(String.trim(tail)),
         {:ok, by} <- by_clause(String.trim(tail)) do
      {:ok, op, args, by, second}
    else
      _ -> {:error, :unsupported_trace_selector}
    end
  end

  # Tempo's second stage: `| topk(n)` or `| bottomk(n)` after the first.
  defp second_stage(text) do
    case Regex.run(~r/\A(.*?)\s*\|\s*(topk|bottomk)\s*\(\s*([0-9]{1,6})\s*\)\z/s, text) do
      [_, rest, op, k] when k != "0" -> {rest, {op, String.to_integer(k)}}
      _ -> {text, nil}
    end
  end

  defp strip_hints(text), do: String.replace(text, ~r/\s*with\s*\([^()]*\)\s*\z/, "")

  defp by_clause(""), do: {:ok, []}

  defp by_clause(text) do
    case Regex.run(~r/\Aby\s*\(([^()]*)\)\z/, text) do
      [_, list] -> {:ok, list |> String.split(",") |> Enum.map(&String.trim/1)}
      _ -> :error
    end
  end

  defp arguments(op, args) when op in ["rate", "count_over_time"] do
    if String.trim(args) == "", do: {:ok, nil, []}, else: :error
  end

  defp arguments("quantile_over_time", args) do
    args
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> case do
      [attr | qs] when qs != [] ->
        with {:ok, value} <- attribute(attr),
             {:ok, qs} <- quantiles(qs),
             do: {:ok, value, qs}

      _ ->
        :error
    end
  end

  defp arguments(_op, args) do
    with {:ok, value} <- attribute(String.trim(args)), do: {:ok, value, []}
  end

  defp quantiles(values) do
    Enum.reduce_while(values, {:ok, []}, fn text, {:ok, acc} ->
      case quantile(text) do
        {:ok, q} -> {:cont, {:ok, [q | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, qs} -> {:ok, Enum.reverse(qs)}
      error -> error
    end
  end

  # TraceQL allows a leading `.` (`.9`), which `Float.parse/1` does not.
  defp quantile(text) do
    case Float.parse(if String.starts_with?(text, "."), do: "0" <> text, else: text) do
      {q, ""} when q >= 0 and q <= 1 -> {:ok, q}
      _ -> :error
    end
  end

  defp attribute(text) do
    case Regex.run(@attribute, text) do
      [_, scope, key] -> {:ok, {scope, key}}
      [_, "", "", key] -> {:ok, {"unscoped", key}}
      [_, "", "", "", intrinsic] -> {:ok, {"intrinsic", intrinsic}}
      _ -> :error
    end
  end

  defp group_by(attributes) when length(attributes) <= 5 do
    Enum.reduce_while(attributes, {:ok, []}, fn text, {:ok, acc} ->
      case attribute(text) do
        {:ok, {scope, key}} -> {:cont, {:ok, [{scope, key, label(scope, key, text)} | acc]}}
        :error when text == "span:id" -> {:cont, {:ok, [{"intrinsic", "id", "span:id"} | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, by} -> {:ok, Enum.reverse(by)}
      error -> error
    end
  end

  defp group_by(_attributes), do: {:error, :query_expression_limit}

  defp label("unscoped", key, _text), do: "." <> key
  defp label("intrinsic", key, _text), do: key
  defp label(scope, key, _text), do: scope <> "." <> key
end
