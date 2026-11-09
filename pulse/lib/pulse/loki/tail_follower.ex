defmodule Pulse.Loki.TailFollower do
  @moduledoc """
  Delivers one tenant's newly published log records to its tailers on this
  node (`Pulse.Loki.Tail`).

  Records arrive two ways:

    * every `:poll_interval_ms` (default 1000), `Pulse.Storage.follow_logs/2`
      reads log segments published since the last poll by any instance;
    * this node's acknowledged appends arrive right away from
      `Pulse.Loki.Tail.publish/2`.

  The same record therefore usually arrives twice. Records already delivered
  in the last `@dedupe_window_ms` are skipped, identified like Loki identifies
  duplicate entries: by exact timestamp, stream labels and line, not a hash.
  The cache retains at most 200,000 entries and 16 MiB of identity payload;
  older identities are evicted as each entry arrives. These are cache bounds,
  not a total process-memory guarantee. Compaction outputs are never read;
  compaction's event-time settle age is not proof that originals were observed.
  Late publications and failed polls can be missed. More than 64 unseen sources
  closes streams explicitly rather than silently advancing a partial cursor.

  The follower stops once the tenant has had no tailers for two polls.
  """

  use GenServer, restart: :temporary

  alias Pulse.LogQL.Entry
  alias Pulse.Loki.Tail
  alias Pulse.Loki.TailDelivery
  alias Pulse.Runtime
  alias Pulse.Storage

  require Logger

  @dedupe_window_ms 120_000
  @dedupe_max 200_000
  @dedupe_max_bytes 16 * 1024 * 1024

  def start_link({tenant, runtime}) do
    Runtime.with(runtime, fn ->
      credit = TailDelivery.new()

      GenServer.start_link(__MODULE__, {tenant, runtime},
        name: {:via, Registry, {Runtime.name(Tail.FollowerRegistry), tenant, credit}}
      )
    end)
  end

  @doc false
  def child_spec(arg), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [arg]}, restart: :temporary}

  @impl true
  def init({tenant, runtime}) do
    Runtime.install(runtime)
    config = Runtime.get_env(:pulse, Tail, [])

    state = %{
      tenant: tenant,
      interval: Keyword.get(config, :poll_interval_ms, 1_000),
      cursor: nil,
      idle: 0,
      delivered: %{},
      identity_bytes: 0,
      order: :queue.new()
    }

    # Mark what is already published before any tailer reads its history,
    # so everything published afterwards counts as new.
    state = poll(state)
    schedule(state)
    {:ok, state}
  end

  @impl true
  def handle_info({:published, credit, bytes, records}, state) do
    TailDelivery.release(credit, bytes)
    {:noreply, deliver(state, records)}
  end

  def handle_info({:published, records}, state), do: {:noreply, deliver(state, records)}

  def handle_info(:poll, state) do
    idle = if Tail.tailers(state.tenant) == [], do: state.idle + 1, else: 0

    if idle >= 2 do
      {:stop, :normal, state}
    else
      state = poll(%{state | idle: idle})
      schedule(state)
      {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp schedule(state), do: Process.send_after(self(), :poll, state.interval)

  defp poll(state) do
    case Storage.follow_logs(state.tenant, state.cursor) do
      {:ok, records, cursor} ->
        deliver(%{state | cursor: cursor}, records)

      {:error, :tail_lag_limit} ->
        # A partial poll could silently lose its unread sources to compaction.
        # Close the stream explicitly; reconnects establish a new baseline and
        # query history rather than pretending this live cursor stayed complete.
        Tail.close(state.tenant)
        %{state | cursor: nil}

      {:error, reason} ->
        Logger.debug("live tail could not follow storage: #{inspect(reason)}")
        state
    end
  end

  defp deliver(state, []), do: state

  defp deliver(state, records) do
    now = System.monotonic_time(:millisecond)
    state = forget(state, now)

    {fresh, state} =
      Enum.reduce(records, {[], state}, fn record, {fresh, acc} ->
        key = identity(record)

        if Map.has_key?(acc.delivered, key),
          do: {fresh, acc},
          else: {[record | fresh], remember(acc, detach(key), now)}
      end)

    if fresh != [] do
      batch = Enum.reverse(fresh)
      Tail.deliver(state.tenant, batch)
    end

    state
  end

  defp identity(record) do
    entry = Entry.from_record(record)
    {entry.timestamp_ns, entry.labels, entry.line}
  end

  # Keep exact values, reusing standalone binaries and detaching only slices
  # that would pin a larger request/column arena. Duplicates never need a copy.
  defp detach({timestamp, labels, line}), do: {timestamp, Pulse.JSON.detach(labels), Pulse.JSON.detach(line)}

  defp remember(state, {_timestamp, labels, line} = key, now) do
    bytes = Enum.reduce(labels, 8 + byte_size(line), fn {name, value}, n -> n + byte_size(name) + byte_size(value) end)

    %{
      state
      | delivered: Map.put(state.delivered, key, now),
        identity_bytes: state.identity_bytes + bytes,
        order: :queue.in({now, key, bytes}, state.order)
    }
    |> forget(now)
  end

  # Forget identities older than the window, and the oldest beyond the cap.
  defp forget(state, now) do
    case :queue.peek(state.order) do
      {:value, {at, key, bytes}}
      when now - at > @dedupe_window_ms or map_size(state.delivered) > @dedupe_max or
             state.identity_bytes > @dedupe_max_bytes ->
        forget(
          %{
            state
            | delivered: Map.delete(state.delivered, key),
              identity_bytes: state.identity_bytes - bytes,
              order: :queue.drop(state.order)
          },
          now
        )

      _ ->
        state
    end
  end
end
