defmodule Pulse.PromQL.NativeRange do
  @moduledoc """
  Range functions over native histogram samples, following Prometheus 3.5.0
  (`promql/functions.go`: `extrapolatedRate`, `histogramRate`,
  `instantValue`, `funcSumOverTime`, `funcAvgOverTime`).

  Callers pass windows whose samples are all histograms; windows that mix
  floats and histograms produce no result, as in Prometheus. Incompatible
  histograms (custom mixed with exponential buckets) also produce no result.
  Addition and subtraction reconcile differing custom bounds to their
  intersection, as in Mimir dd039cdd. Custom reset detection compares plain
  bucket totals at the common boundaries instead of treating layout changes
  alone as resets.

  Counter extrapolation additionally follows Mimir dd039cdd's count-based
  zero-point limit. It bounds the shared factor, not individual buckets or
  the sum; gauges (`delta`) and instantaneous rates remain unchanged.
  Sum/avg use Mimir's compensated histogram accumulation; averages switch
  from direct to weighted incremental means only on histogram-field overflow.
  """

  alias Pulse.PromQL.NativeHistogram, as: H
  alias Pulse.PromQL.Number
  alias Pulse.PromQL.Time
  alias Pulse.Record.NativeHistogram

  @doc """
  `rate`, `increase`, `delta`, `irate`, `idelta`, `sum_over_time` or
  `avg_over_time` of `samples`, or nil. For extrapolated functions, `notice`
  receives schema/type findings and executed reconciliation events. The caller
  owns query-local diagnostics and charges admitted bucket work before entry.
  """
  def value(op, samples, start, finish, notice \\ fn _ -> :ok end)

  def value(op, samples, start, finish, notice) when op in [:rate, :increase, :delta] do
    if length(samples) >= 2, do: extrapolated(op, samples, start, finish, notice)
  end

  def value(:irate, samples, _start, _finish, _notice) do
    case Enum.take(samples, -2) do
      [first, last] when last.timestamp_ns > first.timestamp_ns ->
        change =
          if H.detect_reset?(last.value, first.value),
            do: {:ok, last.value},
            else: H.sub(last.value, first.value)

        case change do
          {:ok, h} ->
            h
            |> gauge()
            |> H.compact()
            |> H.divide(Time.seconds(last.timestamp_ns - first.timestamp_ns))

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  def value(:idelta, samples, _start, _finish, _notice) do
    case Enum.take(samples, -2) do
      [first, last] when last.timestamp_ns > first.timestamp_ns ->
        case H.sub(last.value, first.value) do
          {:ok, h} -> h |> gauge() |> H.compact()
          _ -> nil
        end

      _ ->
        nil
    end
  end

  def value(:sum_over_time, samples, _start, _finish, _notice), do: aggregate(:sum, Enum.map(samples, & &1.value))
  def value(:avg_over_time, samples, _start, _finish, _notice), do: aggregate(:avg, Enum.map(samples, & &1.value))

  @doc "The `sum` or `avg` of `histograms`, or nil when they are incompatible."
  def aggregate(:sum, [first | rest]) do
    rest
    |> Enum.reduce_while({:ok, first, nil}, fn h, {:ok, sum, correction} ->
      case H.compensated_add(sum, h, correction) do
        {:ok, _, _} = ok -> {:cont, ok}
        error -> {:halt, error}
      end
    end)
    |> finish_aggregation()
  end

  # Direct compensated mean until any histogram field overflows, then switch
  # to a weighted incremental mean using the last nonoverflowed accumulator.
  def aggregate(:avg, [first | rest]) do
    state = %{value: first, correction: nil, count: 1, incremental?: false}

    rest
    |> Enum.reduce_while({:ok, state}, fn h, {:ok, state} ->
      case average_step(h, %{state | count: state.count + 1}) do
        {:ok, _} = ok -> {:cont, ok}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, state} ->
        divisor = if state.incremental?, do: 1, else: state.count
        correction = if state.correction, do: H.divide(state.correction, divisor)
        finish_aggregation({:ok, H.divide(state.value, divisor), correction})

      _ ->
        nil
    end
  end

  defp average_step(h, %{incremental?: false} = state) do
    with {:ok, sum, correction} <- H.compensated_add(state.value, h, state.correction) do
      if H.overflow?(sum) do
        incremental_average(h, state)
      else
        {:ok, %{state | value: sum, correction: correction}}
      end
    end
  end

  defp average_step(h, state) do
    q = (state.count - 1) / state.count
    correction = if state.correction, do: H.scale(state.correction, q)

    with {:ok, mean, correction} <- H.compensated_add(H.scale(state.value, q), H.divide(h, state.count), correction) do
      {:ok, %{state | value: mean, correction: correction}}
    end
  end

  defp incremental_average(h, state) do
    correction = if state.correction, do: H.divide(state.correction, state.count - 1)
    mean = H.divide(state.value, state.count - 1)
    average_step(h, %{state | value: mean, correction: correction, incremental?: true})
  end

  defp finish_aggregation({:ok, h, nil}), do: h
  defp finish_aggregation({:ok, h, correction}), do: ok_or_nil(H.add(h, correction))
  defp finish_aggregation(_), do: nil

  defp extrapolated(op, samples, start, finish, notice) do
    counter? = op != :delta

    case change(Enum.map(samples, & &1.value), counter?) do
      {:ok, h, notices} ->
        Enum.each(notices, notice)
        first = hd(samples).timestamp_ns
        last = List.last(samples).timestamp_ns
        interval = Time.seconds(last - first)
        average = interval / (length(samples) - 1)
        left = boundary(Time.seconds(first - start), average)
        right = boundary(Time.seconds(finish - last), average)

        left =
          if counter? and Number.compare(">", h.count, 0) and Number.compare(">=", hd(samples).value.count, 0) do
            zero = Number.multiply(interval, Number.divide(hd(samples).value.count, h.count))
            Number.min(left, zero)
          else
            left
          end

        factor = (interval + left + right) / interval
        factor = if op == :rate, do: factor / Time.seconds(finish - start), else: factor
        H.scale(h, factor)

      {:error, notices} ->
        Enum.each(notices, notice)
        nil
    end
  end

  defp boundary(distance, average), do: if(distance >= average * 1.1, do: average / 2, else: distance)

  # histogramRate: the last histogram minus the first, reconciled to the
  # lowest schema in the window, plus every value lost to a counter reset.
  defp change([first, second | _] = histograms, counter?) do
    last = List.last(histograms)
    endpoint_gauge? = counter? and Enum.any?([first, last], &(&1.counter_reset_hint == :gauge))
    endpoint_notices = if endpoint_gauge?, do: [:not_counter], else: []

    # A reset between the first two samples makes the first irrelevant.
    first =
      if counter? and H.detect_reset?(second, first),
        do: %NativeHistogram{schema: second.schema, custom_values: second.custom_values},
        else: first

    # Counters reconcile every sample; gauges only the two they subtract.
    middle = if counter?, do: Enum.slice(histograms, 1..-2//1), else: []
    custom? = &(&1.schema == NativeHistogram.custom_buckets_schema())

    cond do
      custom?.(last) != custom?.(first) ->
        {:error, [:mixed_schema | endpoint_notices]}

      Enum.any?(middle, &(custom?.(&1) != custom?.(first))) ->
        # Upstream replaces earlier endpoint/gauge notices on a failed middle
        # schema. Keep this local until the entire schema pass succeeds.
        {:error, [:mixed_schema]}

      true ->
        subtract_and_correct(first, last, middle, counter?, endpoint_gauge?)
    end
  end

  # Called only after the full schema pass; collect notices from the actual
  # subtraction and reset additions, not from layouts in unexecuted branches.
  defp subtract_and_correct(first, last, middle, counter?, endpoint_gauge?) do
    lowest = [first, last | middle] |> Enum.map(& &1.schema) |> Enum.min()
    {:ok, h} = H.sub(H.reduce_resolution(last, lowest), first)

    notices =
      if first.schema == NativeHistogram.custom_buckets_schema() and first.custom_values != last.custom_values,
        do: MapSet.new([:reconciled_subtraction]),
        else: MapSet.new()

    notices =
      if endpoint_gauge? or (counter? and Enum.any?(middle, &(&1.counter_reset_hint == :gauge))),
        do: MapSet.put(notices, :not_counter),
        else: notices

    {h, notices} = if counter?, do: add_resets(h, [first | middle] ++ [last], notices), else: {h, notices}
    {:ok, h |> gauge() |> H.compact(), notices}
  end

  defp add_resets(h, [previous | rest], notices) do
    rest
    |> Enum.reduce({h, previous, notices}, &add_reset/2)
    |> then(fn {h, _, notices} -> {h, notices} end)
  end

  # Each counter reset loses the value before it; add that back.
  defp add_reset(current, {acc, previous, notices}) do
    if H.detect_reset?(current, previous) do
      notices =
        if acc.schema == NativeHistogram.custom_buckets_schema() and acc.custom_values != previous.custom_values,
          do: MapSet.put(notices, :reconciled_addition),
          else: notices

      # The schema pass has already proven that every operand is compatible.
      {:ok, acc} = H.add(acc, previous)
      {acc, current, notices}
    else
      {acc, current, notices}
    end
  end

  defp gauge(h), do: %{h | counter_reset_hint: :gauge}

  defp ok_or_nil({:ok, h}), do: h
  defp ok_or_nil(_), do: nil
end
