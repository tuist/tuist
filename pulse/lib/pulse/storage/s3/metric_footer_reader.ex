defmodule Pulse.Storage.S3.MetricFooterReader do
  @moduledoc false
  alias Pulse.Codec.NIF
  alias Pulse.ObjectStore

  defstruct [:body, :rows, :charge]

  @probe 65_536
  @max_footer 1_048_576
  @max_source 134_217_728

  # Each source costs at least its entire logical size, or all transferred
  # bytes if larger. Exclusion must not silently relax source admission.
  def read(config, key, start, finish, matchers, opts) do
    context = %{
      config: config,
      key: key,
      start: start,
      finish: finish,
      matchers: matchers,
      limit: min(opts[:max_scan_bytes] || @max_source, @max_source),
      row_limit: min(opts[:max_scan_rows] || 1_000_000, 1_000_000),
      deadline: opts[:deadline_ms]
    }

    with {:ok, tag, size, tail} <- fetch(context, nil, @probe, context.limit) do
      inspect_tail(context, %{
        tag: tag,
        size: size,
        tail: tail,
        transferred: byte_size(tail),
        expanded?: false,
        rows: nil
      })
    end
  end

  defp inspect_tail(ctx, scan) do
    with :ok <- budget(logical_charge(scan), ctx.limit), :ok <- deadline(ctx.deadline) do
      plan = NIF.metric_segment_footer_plan(scan.tail, scan.size, ctx.start, ctx.finish, ctx.matchers)
      apply_plan(ctx, scan, plan)
    end
  end

  defp apply_plan(ctx, %{expanded?: false} = scan, {:ok, :more, required}) when required <= @max_footer do
    cost = max(scan.size, scan.transferred + min(required, scan.size))

    with :ok <- budget(cost, ctx.limit) do
      case fetch(ctx, scan.tag, required, ctx.limit) do
        {:ok, tag, size, tail} when tag == scan.tag and size == scan.size ->
          inspect_tail(ctx, %{scan | tail: tail, transferred: scan.transferred + byte_size(tail), expanded?: true})

        {:ok, _, _, _} ->
          {:error, :precondition_failed}

        error ->
          missing_cost(error, cost, 0)
      end
    end
  end

  defp apply_plan(ctx, scan, {:ok, rows, empty?}) when is_integer(rows) and is_boolean(empty?) do
    with :ok <- budget(rows, ctx.row_limit), :ok <- deadline(ctx.deadline) do
      read_choice(ctx, %{scan | rows: rows}, empty?)
    end
  end

  defp apply_plan(ctx, scan, _unknown), do: full(ctx, scan)

  defp read_choice(_ctx, scan, true), do: {:ok, %__MODULE__{body: nil, rows: scan.rows, charge: logical_charge(scan)}}
  defp read_choice(ctx, scan, false), do: full(ctx, scan)

  defp full(ctx, scan) do
    complete? = byte_size(scan.tail) == scan.size
    cost = if complete?, do: logical_charge(scan), else: scan.size + scan.transferred

    with :ok <- budget(cost, ctx.limit), :ok <- deadline(ctx.deadline) do
      finish_full(ctx, scan, cost, full_snapshot(ctx, scan, complete?))
    end
  end

  defp full_snapshot(_ctx, scan, true), do: {:ok, scan.tag, scan.size, scan.tail}
  defp full_snapshot(ctx, scan, false), do: fetch(ctx, scan.tag, 0, ctx.limit - scan.transferred)

  defp finish_full(ctx, scan, cost, {:ok, tag, size, body}) when tag == scan.tag and size == scan.size do
    with :ok <- deadline(ctx.deadline),
         {:ok, rows} <- rows(scan.rows, body),
         :ok <- budget(rows, ctx.row_limit),
         :ok <- deadline(ctx.deadline) do
      {:ok, %__MODULE__{body: body, rows: rows, charge: cost}}
    end
  end

  defp finish_full(_ctx, _scan, _cost, {:ok, _, _, _}), do: {:error, :precondition_failed}
  defp finish_full(_ctx, scan, cost, error), do: missing_cost(error, cost, scan.rows || 0)

  defp rows(nil, body) do
    case NIF.metric_segment_parquet_row_count(body) do
      {:ok, count} -> {:ok, count}
      _ -> {:error, {:decode_failed, :parquet_decoder_rejected_input}}
    end
  end

  defp rows(count, _body), do: {:ok, count}

  defp fetch(ctx, tag, suffix, limit) do
    with :ok <- budget(1, limit), :ok <- deadline(ctx.deadline) do
      timeout = if ctx.deadline, do: min(15_000, ctx.deadline - System.monotonic_time(:millisecond)), else: 15_000

      case ObjectStore.get_snapshot(ctx.config, ctx.key, tag, suffix, limit, max(timeout, 1)) do
        {:error, :response_too_large} -> {:error, :query_scan_limit}
        {:error, :timeout} -> {:error, :query_timeout}
        other -> other
      end
    end
  end

  defp logical_charge(scan), do: max(scan.size, scan.transferred)
  defp missing_cost({:error, :not_found}, cost, rows), do: {:error, {:footer_source_missing, cost, rows}}
  defp missing_cost(error, _cost, _rows), do: error
  defp budget(value, max) when value <= max, do: :ok
  defp budget(_value, _max), do: {:error, :query_scan_limit}
  defp deadline(nil), do: :ok

  defp deadline(value) do
    if System.monotonic_time(:millisecond) < value, do: :ok, else: {:error, :query_timeout}
  end
end
