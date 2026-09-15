defmodule TuistCommon.Ingestion.Buffer do
  @moduledoc """
  Per-schema RowBinary buffer that trades N synchronous ClickHouse
  inserts for one batched flush.

  Instances are created by `TuistCommon.Ingestion.Bufferable` on any
  Ecto schema tagged with `use TuistCommon.Ingestion.Bufferable,
  otp_app: :my_app, repo: MyApp.IngestRepo`. Rows accumulate as
  `Ch.RowBinary` iodata; flushes go through `repo.query/3` as a
  single `INSERT ... FORMAT RowBinaryWithNamesAndTypes`, so the
  pool's queue sees one checkout per interval rather than one per
  row.

  Defaults for `flush_interval_ms` / `max_buffer_size` / `sync_writes`
  are read from the caller's `Application.get_env(otp_app, repo, [])`.

  Emits `[:tuist_common, :ingestion, :buffer, :dropped]` when a
  shutdown flush is rejected and buffered bytes are lost. Subscribe
  from any host.
  """

  use GenServer

  require Logger

  @dropped_event [:tuist_common, :ingestion, :buffer, :dropped]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def insert!(server, row_binary) do
    case GenServer.call(server, {:insert, row_binary}, :infinity) do
      :ok ->
        :ok

      {:error, %{__exception__: true} = error} ->
        raise error

      {:error, error} ->
        raise "ClickHouse ingestion buffer rejected an insert: #{inspect(error)}"
    end
  end

  def flush(server) do
    GenServer.call(server, :flush, :infinity)
  end

  @impl true
  def init(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    repo = Keyword.fetch!(opts, :repo)
    repo_config = repo_config(otp_app, repo)

    buffer = opts[:buffer] || []
    max_buffer_size = opts[:max_buffer_size] || default_max_buffer_size(repo_config)
    retained_buffer_size = opts[:retained_buffer_size] || max_buffer_size * 2
    flush_interval_ms = opts[:flush_interval_ms] || default_flush_interval_ms(repo_config)

    Process.flag(:trap_exit, true)
    timer = Process.send_after(self(), :tick, flush_interval_ms)

    {:ok,
     %{
       repo: repo,
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
       memory_retries: Keyword.get(opts, :memory_retries, 1),
       sync_writes?: Keyword.get(opts, :sync_writes, sync_writes?(repo_config)),
       flush_deferred?: false
     }}
  end

  @impl true
  def handle_call({:insert, row_binary}, _from, %{sync_writes?: true} = state) do
    candidate_state = %{
      state
      | buffer: [state.buffer | row_binary],
        buffer_size: state.buffer_size + IO.iodata_length(row_binary)
    }

    if candidate_state.buffer_size > state.retained_buffer_size do
      handle_capacity_pressure(row_binary, state)
    else
      case do_flush(candidate_state) do
        :ok ->
          {:reply, :ok, cleared_buffer(candidate_state)}

        {:error, error} ->
          log_deferred_flush(candidate_state, error)
          {:reply, {:error, error}, %{candidate_state | flush_deferred?: true}}
      end
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

        :telemetry.execute(@dropped_event, %{bytes: state.buffer_size}, %{buffer: name})
    end
  end

  @doc """
  Telemetry event emitted when a shutdown flush is rejected and
  buffered bytes are lost.
  """
  def dropped_event, do: @dropped_event

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
      repo: repo,
      buffer: buffer,
      buffer_size: buffer_size,
      insert_opts: insert_opts,
      insert_sql: insert_sql,
      header: header,
      name: name,
      memory_retries: memory_retries
    } = state

    case buffer do
      [] ->
        :ok

      _not_empty ->
        Logger.notice("Flushing #{buffer_size} byte(s) RowBinary from #{name}")

        operation = fn ->
          repo.query(insert_sql, [header | buffer], insert_opts)
        end

        flush_result =
          TuistCommon.ClickHouseRetry.with_result_retry(operation,
            memory_retries: memory_retries
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
    TuistCommon.ClickHouseRetry.memory_limit_error?(error) or
      is_struct(error, Mint.TransportError) or
      is_struct(error, DBConnection.ConnectionError)
  end

  defp error_message(%{__exception__: true} = error), do: Exception.message(error)
  defp error_message(error), do: inspect(error)

  defp repo_config(otp_app, repo) do
    case Application.get_env(otp_app, repo) do
      config when is_list(config) -> config
      _ -> []
    end
  end

  defp default_flush_interval_ms(repo_config) do
    Keyword.fetch!(repo_config, :flush_interval_ms)
  end

  defp default_max_buffer_size(repo_config) do
    Keyword.fetch!(repo_config, :max_buffer_size)
  end

  defp sync_writes?(repo_config), do: Keyword.get(repo_config, :sync_writes, false)
end
