defmodule Pulse.QueryRunner do
  @moduledoc """
  Runs public queries in supervised, bounded tasks. Registry ownership stays with
  the worker, including when a native call outlives the request deadline.

  The caller returns at the deadline: a worker still running is killed, but the
  caller does not wait for it to exit, so a native call that cannot be
  preempted holds its slot, never the response. The limit a query hit
  (`Pulse.QueryLimit`) is carried back into the calling process.
  """

  alias Pulse.PromQL.Evaluator
  alias Pulse.PromQL.QuerySlots
  alias Pulse.PromQL.TaskSupervisor
  alias Pulse.QueryLimit
  alias Pulse.Runtime
  alias Pulse.Runtime.Registry
  alias Pulse.Runtime.Task

  @queue_poll_ms 20

  def run(tenant, class, fun, opts \\ %{}) when is_binary(tenant) and is_function(fun, 1) do
    with {:ok, timeout} <- timeout(opts) do
      started = System.monotonic_time(:millisecond)
      deadline = started + timeout
      # A limit detail belongs to the query that recorded it.
      _ = QueryLimit.take()

      task =
        try do
          Task.Supervisor.async_nolink(TaskSupervisor, fn ->
            Process.set_label({:pulse, :query})

            Process.flag(:max_heap_size, %{
              size: heap_words(class),
              kill: true,
              error_logger: false
            })

            scope = if class == :reliability_callback, do: {:reliability_callback, tenant}, else: tenant

            per_tenant = Pulse.TenantLimits.get(tenant, :query_max_concurrent) || config(:max_per_tenant, 2)
            # Dashboards send their panels at once: wait up to `:queue_ms` for a
            # free slot (leaving time to answer) instead of refusing at once.
            queue_until = min(started + config(:queue_ms, 0), deadline - 1_000)

            result =
              with :ok <- acquire({scope}, per_tenant, queue_until),
                   :ok <- acquire_interactive(class, queue_until),
                   :ok <- acquire({:class, class}, class_limit(class), queue_until) do
                fun.(deadline)
              end

            # Hand which budget failed back to the caller with the result.
            {__MODULE__, result, QueryLimit.take()}
          end)
        rescue
          RuntimeError -> nil
        end

      result = task |> await(max(1, deadline - System.monotonic_time(:millisecond)), timeout, class) |> unwrap(timeout)
      # Refused queries are not metered; everything admitted is, whatever its outcome.
      if result != {:error, :query_overloaded},
        do: Pulse.Usage.query(tenant, System.monotonic_time(:millisecond) - started)

      result
    end
  end

  def storage_opts(deadline, max_records \\ 100_000) do
    [
      max_records: max_records,
      max_scan_segments: max_scan_segments(),
      max_scan_bytes: config(:max_scan_bytes, 134_217_728),
      max_scan_rows: config(:max_scan_rows, 1_000_000),
      deadline_ms: deadline
    ]
  end

  @doc "Stored segments one query may read; `PULSE_QUERY_MAX_SCAN_SEGMENTS`."
  def max_scan_segments, do: config(:max_scan_segments, 1024)

  # Storage reports its own deadline checks only as :query_timeout.
  defp unwrap({__MODULE__, {:error, :query_timeout} = result, nil}, timeout) do
    QueryLimit.record(:timeout_ms, timeout, nil)
    result
  end

  defp unwrap({__MODULE__, result, detail}, _timeout) do
    QueryLimit.put(detail)
    result
  end

  defp unwrap(result, _timeout), do: result

  defp await(nil, _wait, _timeout, _class), do: {:error, :query_overloaded}

  defp await(task, wait, timeout, class) do
    case Task.yield(task, wait) do
      {:ok, result} ->
        result

      {:exit, :killed} ->
        QueryLimit.record(:max_heap_mb, div(heap_words(class) * 8, 1_048_576), nil)
        {:error, :query_resource_limit}

      {:exit, _} ->
        {:error, :query_execution_failed}

      nil ->
        # Task.shutdown/2 waits for the worker to exit, which a long native call
        # delays well past the deadline. Kill it and answer now instead.
        Process.exit(task.pid, :kill)
        Task.ignore(task)
        QueryLimit.record(:timeout_ms, timeout, nil)
        {:error, :query_timeout}
    end
  end

  defp timeout(opts) do
    case Map.get(opts, :timeout_ms, config(:timeout_ms, 10_000)) do
      ms when is_integer(ms) and ms > 0 -> {:ok, min(ms, config(:timeout_ms, 10_000))}
      _ -> {:error, :invalid_timeout}
    end
  end

  @doc "Interactive queries holding a slot on this node."
  def interactive_in_flight do
    QuerySlots |> Registry.select([{{{:class, :interactive, :_}, :_, :_}, [], [true]}]) |> length()
  rescue
    ArgumentError -> 0
  end

  @doc "This node's interactive query slot count."
  def max_interactive, do: config(:max_interactive, 3)

  defp acquire(key, max, queue_until) do
    with {:error, :query_overloaded} = error <-
           if(is_integer(max) and max >= 1, do: acquire_slot(key, max, 0), else: {:error, :query_overloaded}) do
      if System.monotonic_time(:millisecond) + @queue_poll_ms <= queue_until do
        Process.sleep(@queue_poll_ms)
        acquire(key, max, queue_until)
      else
        Pulse.SelfMetrics.admission_rejection(:query, rejection_reason(key))
        error
      end
    end
  end

  defp rejection_reason({_tenant}), do: :tenant
  defp rejection_reason({:class, :interactive}), do: :node
  defp rejection_reason({:class, _class}), do: :class
  defp acquire_slot(_key, max, max), do: {:error, :query_overloaded}

  defp acquire_slot(key, max, slot) do
    registry_key =
      case key do
        {tenant} -> {tenant, slot}
        {:class, class} -> {:class, class, slot}
      end

    case Registry.register(QuerySlots, registry_key, nil) do
      {:ok, _} -> :ok
      {:error, {:already_registered, _}} -> acquire_slot(key, max, slot + 1)
    end
  end

  defp config(key, default), do: Keyword.get(Runtime.get_env(:pulse, __MODULE__, []), key, default)

  defp acquire_interactive(class, _queue_until) when class in [:alerting, :reliability_callback], do: :ok

  # Under node memory pressure new interactive queries are refused (retryable)
  # so ingest keeps its memory; alerting and reliability workers still run.
  defp acquire_interactive(_class, queue_until) do
    if Pulse.MemoryPressure.active?() do
      Pulse.SelfMetrics.admission_rejection(:query, :memory)
      {:error, :query_overloaded}
    else
      acquire({:class, :interactive}, max_interactive(), queue_until)
    end
  end

  defp class_limit(class) do
    default = if class in [:raw, :discovery, :alerting, :reliability_callback], do: 1, else: 3
    Map.get(config(:class_limits, %{}), class, default)
  end

  defp heap_words(class) when class in [:promql, :alerting] do
    Keyword.get(Runtime.get_env(:pulse, Evaluator, []), :max_heap_words, config(:max_heap_words, 16_000_000))
  end

  defp heap_words(_class), do: config(:max_heap_words, 16_000_000)
end
