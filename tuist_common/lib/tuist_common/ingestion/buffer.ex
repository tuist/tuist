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

  # `shutdown: :infinity` lets the supervisor wait for the buffer's own
  # self-bounded drain to finish, instead of imposing a second, tighter
  # deadline from the OTP layer. The drain caps itself: exponential
  # backoff between attempts, hard stop after `@shutdown_max_attempts`,
  # so a wedged ClickHouse can never hang the shutdown. The pod's
  # `terminationGracePeriodSeconds` remains the outer safety net.
  use GenServer, shutdown: :infinity

  require Logger

  @dropped_event [:tuist_common, :ingestion, :buffer, :dropped]
  @shutdown_retry_event [:tuist_common, :ingestion, :buffer, :shutdown_retry]
  # Bounded shutdown-flush retry budget. Defaults picked so a slow
  # ClickHouse gets a real chance to drain the tail (~30 s of wall
  # time in the worst case) without letting a wedged one hold the
  # process open indefinitely.
  @shutdown_max_attempts 8
  @shutdown_initial_delay_ms 250
  @shutdown_max_delay_ms 5_000

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
    drain_until_empty(state)
  end

  @doc """
  Telemetry event emitted when a shutdown flush is rejected and
  buffered bytes are lost. Emitted only on the terminal path where the
  buffer is confirmed empty or the process observes an unrecoverable
  drop; kubelet SIGKILLs bypass this and surface via the container
  event stream instead.
  """
  def dropped_event, do: @dropped_event

  @doc """
  Telemetry event emitted once per shutdown flush retry so a Grafana
  panel can show the drain tail even when the process is later
  SIGKILLed before `terminate/2` returns.
  """
  def shutdown_retry_event, do: @shutdown_retry_event

  # Bounded shutdown flush with exponential backoff. Each attempt runs
  # `do_flush/1` (which itself retries transport and memory-limit
  # failures inside `ClickHouseRetry`); on a persistent failure the
  # loop sleeps for a doubling delay capped at `@shutdown_max_delay_ms`
  # and tries again. After `@shutdown_max_attempts` we give up: the
  # buffered bytes are logged, counted through the terminal
  # `dropped` telemetry event, and the process is allowed to finish
  # shutting down. Each retry emits its own event so a Grafana panel
  # can see the drain tail while the loop is still running.
  defp drain_until_empty(state), do: drain_until_empty(state, 1)

  defp drain_until_empty(%{buffer: []}, _attempt), do: :ok

  defp drain_until_empty(state, attempt) when attempt > @shutdown_max_attempts do
    Logger.error(
      "Giving up on #{state.name} shutdown flush after #{@shutdown_max_attempts} attempts; dropping #{state.buffer_size} byte(s)"
    )

    :telemetry.execute(@dropped_event, %{bytes: state.buffer_size}, %{buffer: state.name})
  end

  defp drain_until_empty(state, attempt) do
    case do_flush(state) do
      :ok ->
        :ok

      {:error, error} ->
        delay = shutdown_backoff_delay(attempt)

        :telemetry.execute(
          @shutdown_retry_event,
          %{bytes: state.buffer_size, attempt: attempt},
          %{buffer: state.name}
        )

        Logger.warning(
          "Retrying #{state.name} shutdown flush of #{state.buffer_size} byte(s) (attempt #{attempt}/#{@shutdown_max_attempts}, sleep #{delay}ms) after transient failure: #{error_message(error)}"
        )

        Process.sleep(delay)
        drain_until_empty(state, attempt + 1)
    end
  end

  defp shutdown_backoff_delay(attempt) do
    (@shutdown_initial_delay_ms * Integer.pow(2, attempt - 1))
    |> min(@shutdown_max_delay_ms)
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
