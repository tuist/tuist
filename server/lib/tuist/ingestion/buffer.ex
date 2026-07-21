defmodule Tuist.Ingestion.Buffer do
  @moduledoc """
  Batches RowBinary payloads and flushes them to ClickHouse.

  One named process per destination table, shared by every producer on the
  node, which makes its failure modes everyone's failure modes:

    * Callers wait a bounded time, never `:infinity`. An unbounded wait meant a
      stalled ClickHouse silently parked every producer on the node with no
      crash, no error and no telemetry — on the xcresult processor that
      presented as a queue that had simply stopped, with healthy-looking pods,
      recoverable only by redeploying.

    * A failed flush is reported back to the caller instead of raising inside
      the process. Raising here killed the buffer *and* every unrelated caller
      blocked on it, turning one bad insert into a node-wide outage. Now the
      requesting caller fails (its job retries) and everyone else is untouched.

  `flush/2` still raises on failure so callers keep today's fail-the-job
  semantics; what changed is that the buffer survives.
  """

  use GenServer

  alias Tuist.ClickHouseRetry
  alias Tuist.IngestRepo

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def insert(server, row_binary, timeout \\ flush_timeout_ms()) do
    if sync_writes?() do
      server
      |> GenServer.call({:insert_and_flush, row_binary}, timeout)
      |> raise_on_flush_error(server)
    else
      GenServer.cast(server, {:insert, row_binary})
    end
  end

  def flush(server, timeout \\ flush_timeout_ms()) do
    server
    |> GenServer.call(:flush, timeout)
    |> raise_on_flush_error(server)
  end

  defp raise_on_flush_error(:ok, _server), do: :ok

  defp raise_on_flush_error({:error, error}, server) do
    raise RuntimeError,
      message: "Failed to flush #{inspect(server)} buffer to ClickHouse: #{Exception.message(error)}"
  end

  @impl true
  def init(opts) do
    buffer = opts[:buffer] || []
    max_buffer_size = opts[:max_buffer_size] || default_max_buffer_size()
    flush_interval_ms = opts[:flush_interval_ms] || default_flush_interval_ms()

    Process.flag(:trap_exit, true)
    timer = Process.send_after(self(), :tick, flush_interval_ms)

    {:ok,
     %{
       buffer: buffer,
       timer: timer,
       name: Keyword.fetch!(opts, :name),
       insert_sql: Keyword.fetch!(opts, :insert_sql),
       insert_opts: Keyword.fetch!(opts, :insert_opts),
       header: Keyword.fetch!(opts, :header),
       buffer_size: IO.iodata_length(buffer),
       max_buffer_size: max_buffer_size,
       flush_interval_ms: flush_interval_ms
     }}
  end

  @impl true
  def handle_cast({:insert, row_binary}, state) do
    state = %{
      state
      | buffer: [state.buffer | row_binary],
        buffer_size: state.buffer_size + IO.iodata_length(row_binary)
    }

    if state.buffer_size >= state.max_buffer_size do
      Logger.notice("#{state.name} buffer full, flushing to ClickHouse")
      Process.cancel_timer(state.timer)
      log_flush_error(do_flush(state), state)
      new_timer = Process.send_after(self(), :tick, state.flush_interval_ms)
      {:noreply, %{state | buffer: [], timer: new_timer, buffer_size: 0}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    log_flush_error(do_flush(state), state)
    timer = Process.send_after(self(), :tick, state.flush_interval_ms)
    {:noreply, %{state | buffer: [], buffer_size: 0, timer: timer}}
  end

  @impl true
  def handle_call({:insert_and_flush, row_binary}, _from, state) do
    state = %{
      state
      | buffer: [state.buffer | row_binary],
        buffer_size: state.buffer_size + IO.iodata_length(row_binary)
    }

    {:reply, do_flush(state), %{state | buffer: [], buffer_size: 0}}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    %{timer: timer, flush_interval_ms: flush_interval_ms} = state
    Process.cancel_timer(timer)
    result = do_flush(state)
    new_timer = Process.send_after(self(), :tick, flush_interval_ms)
    {:reply, result, %{state | buffer: [], buffer_size: 0, timer: new_timer}}
  end

  @impl true
  def terminate(_reason, %{name: name} = state) do
    Logger.notice("Flushing #{name} buffer before shutdown...")
    log_flush_error(do_flush(state), state)
  end

  defp do_flush(state) do
    %{
      buffer: buffer,
      buffer_size: buffer_size,
      insert_opts: insert_opts,
      insert_sql: insert_sql,
      header: header,
      name: name
    } = state

    case buffer do
      [] ->
        :ok

      _not_empty ->
        Logger.notice("Flushing #{buffer_size} byte(s) RowBinary from #{name}")

        case ClickHouseRetry.with_retry_result(fn ->
               IngestRepo.query(insert_sql, [header | buffer], insert_opts)
             end) do
          {:ok, _result} -> :ok
          {:error, _error} = error -> error
        end
    end
  end

  # Flushes with no caller to answer to — the periodic tick, a full buffer, and
  # shutdown. There is nobody to hand the error to and crashing would take out
  # every unrelated producer waiting on this process, so the batch is dropped
  # and the failure is recorded. Dropping matches what the previous raise-based
  # behaviour did in practice (the supervisor restarted with an empty buffer),
  # minus the collateral damage.
  defp log_flush_error(:ok, _state), do: :ok

  defp log_flush_error({:error, error}, %{name: name, buffer_size: buffer_size}) do
    Logger.error("Dropped #{buffer_size} byte(s) from #{name}: #{Exception.message(error)}")

    :ok
  end

  defp flush_timeout_ms do
    case Application.get_env(:tuist, IngestRepo) do
      config when is_list(config) -> Keyword.get(config, :flush_timeout_ms, 60_000)
      _ -> 60_000
    end
  end

  defp default_flush_interval_ms do
    Keyword.fetch!(Application.get_env(:tuist, IngestRepo), :flush_interval_ms)
  end

  defp default_max_buffer_size do
    Keyword.fetch!(Application.get_env(:tuist, IngestRepo), :max_buffer_size)
  end

  defp sync_writes? do
    case Application.get_env(:tuist, IngestRepo) do
      config when is_list(config) -> Keyword.get(config, :sync_writes, false)
      _ -> false
    end
  end
end
