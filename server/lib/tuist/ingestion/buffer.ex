defmodule Tuist.Ingestion.Buffer do
  @moduledoc false

  use GenServer

  alias Tuist.IngestRepo

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def insert(server, row_binary) do
    GenServer.call(server, {:insert, row_binary}, :infinity)
  end

  def flush(server) do
    GenServer.call(server, :flush, :infinity)
  end

  @impl true
  def init(opts) do
    buffer = opts[:buffer] || []
    max_buffer_size = opts[:max_buffer_size] || default_max_buffer_size()
    retained_buffer_size = opts[:retained_buffer_size] || max_buffer_size * 2
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
       retained_buffer_size: max(retained_buffer_size, max_buffer_size),
       flush_interval_ms: flush_interval_ms,
       user_memory_retries: Keyword.get(opts, :user_memory_retries, 1),
       sync_writes?: Keyword.get(opts, :sync_writes, sync_writes?()),
       flush_deferred?: false
     }}
  end

  @impl true
  def handle_call({:insert, row_binary}, _from, %{sync_writes?: true} = state) do
    state = %{
      state
      | buffer: [state.buffer | row_binary],
        buffer_size: state.buffer_size + IO.iodata_length(row_binary)
    }

    case do_flush(state) do
      :ok ->
        {:reply, :ok, cleared_buffer(state)}

      {:error, error} ->
        log_deferred_flush(state, error)
        {:reply, {:error, error}, %{state | flush_deferred?: true}}
    end
  end

  def handle_call({:insert, row_binary}, _from, %{sync_writes?: false} = state) do
    candidate_state = %{
      state
      | buffer: [state.buffer | row_binary],
        buffer_size: state.buffer_size + IO.iodata_length(row_binary)
    }

    cond do
      candidate_state.buffer_size > state.retained_buffer_size ->
        handle_capacity_pressure(row_binary, state)

      candidate_state.buffer_size >= state.max_buffer_size and not state.flush_deferred? ->
        Logger.notice("#{state.name} buffer full, flushing to ClickHouse")

        case do_flush(candidate_state) do
          :ok ->
            {:reply, :ok, cleared_buffer(candidate_state)}

          {:error, error} ->
            if retryable_flush_error?(error) do
              log_deferred_flush(candidate_state, error)
              {:reply, :ok, %{candidate_state | flush_deferred?: true}}
            else
              {:reply, {:error, error}, state}
            end
        end

      true ->
        {:reply, :ok, candidate_state}
    end
  end

  @impl true
  def handle_call(:flush, _from, state) do
    %{timer: timer, flush_interval_ms: flush_interval_ms} = state
    Process.cancel_timer(timer)
    new_timer = Process.send_after(self(), :tick, flush_interval_ms)

    case do_flush(state) do
      :ok ->
        {:reply, :ok, %{cleared_buffer(state) | timer: new_timer}}

      {:error, error} ->
        log_deferred_flush(state, error)
        {:reply, {:error, error}, %{state | timer: new_timer, flush_deferred?: true}}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    timer = Process.send_after(self(), :tick, state.flush_interval_ms)

    case do_flush(state) do
      :ok ->
        {:noreply, %{cleared_buffer(state) | timer: timer}}

      {:error, error} ->
        log_deferred_flush(state, error)
        {:noreply, %{state | timer: timer, flush_deferred?: true}}
    end
  end

  @impl true
  def terminate(_reason, %{name: name} = state) do
    Logger.notice("Flushing #{name} buffer before shutdown...")

    case do_flush(state) do
      :ok ->
        :ok

      {:error, error} ->
        Logger.error(
          "Dropping #{state.buffer_size} buffered byte(s) from #{name} during shutdown after ClickHouse rejected the final flush: #{error_message(error)}"
        )

        :telemetry.execute(
          Tuist.Telemetry.event_name_ingestion_buffer_dropped(),
          %{bytes: state.buffer_size},
          %{buffer: name}
        )
    end
  end

  defp handle_capacity_pressure(row_binary, state) do
    if state.buffer == [] do
      candidate_state = %{
        state
        | buffer: [row_binary],
          buffer_size: IO.iodata_length(row_binary)
      }

      case do_flush(candidate_state) do
        :ok ->
          {:reply, :ok, cleared_buffer(candidate_state)}

        {:error, error} ->
          {:reply, {:error, error}, state}
      end
    else
      case do_flush(state) do
        :ok ->
          handle_call({:insert, row_binary}, self(), cleared_buffer(state))

        {:error, error} ->
          log_deferred_flush(state, error)
          {:reply, {:error, error}, %{state | flush_deferred?: true}}
      end
    end
  end

  defp do_flush(state) do
    %{
      buffer: buffer,
      buffer_size: buffer_size,
      insert_opts: insert_opts,
      insert_sql: insert_sql,
      header: header,
      name: name,
      user_memory_retries: user_memory_retries
    } = state

    case buffer do
      [] ->
        :ok

      _not_empty ->
        Logger.notice("Flushing #{buffer_size} byte(s) RowBinary from #{name}")

        operation = fn ->
          IngestRepo.query(insert_sql, [header | buffer], insert_opts)
        end

        flush_result =
          Tuist.ClickHouseRetry.with_result_retry(operation,
            user_memory_retries: user_memory_retries
          )

        case flush_result do
          {:ok, _result} ->
            :ok

          {:error, error} ->
            {:error, error}
        end
    end
  end

  defp cleared_buffer(state) do
    %{state | buffer: [], buffer_size: 0, flush_deferred?: false}
  end

  defp log_deferred_flush(%{name: name, buffer_size: buffer_size}, error) do
    Logger.warning(
      "Deferring #{name} buffer flush with #{buffer_size} byte(s) after a transient ClickHouse failure: #{error_message(error)}"
    )
  end

  defp retryable_flush_error?(error) do
    Tuist.ClickHouseRetry.user_memory_limit_error?(error) or
      is_struct(error, Mint.TransportError) or
      is_struct(error, DBConnection.ConnectionError)
  end

  defp error_message(%{__exception__: true} = error), do: Exception.message(error)
  defp error_message(error), do: inspect(error)

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
