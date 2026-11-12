defmodule PulseWeb.LokiTail do
  @moduledoc """
  WebSocket side of `GET /loki/api/v1/tail`.

  The connection process is already one of the tenant's `Pulse.Loki.Tail`
  tailers when the socket opens, and its first frame holds the historical
  entries the controller read. Every later frame carries the live entries
  one delivered batch contributed, in Loki's tail shape:
  `{"streams": [...], "dropped_entries": [...] | null}`. If the tenant's
  follower exits, the socket closes with code 1013. A new follower's baseline
  cannot prove continuity with this socket's previous live cursor.

  When more than `:max_backlog` batches wait in the mailbox, batches are
  dropped unfiltered and reported, up to `@max_dropped_reported` per frame,
  as dropped entries with their stream labels.
  """

  @behaviour WebSock

  alias Pulse.LogQL.Entry
  alias Pulse.Loki.Tail
  alias Pulse.Loki.TailDelivery
  alias Pulse.Record.Log

  @ping_interval_ms 30_000
  @max_dropped_reported 100

  @impl true
  def init(state) do
    schedule_ping()
    Process.monitor(state.follower)
    {:push, {:text, frame(state.history, [])}, Map.delete(state, :history)}
  end

  @impl true
  def handle_in(_frame, state), do: {:ok, state}

  @impl true
  def handle_info({Tail, credit, bytes, records}, state) do
    TailDelivery.release(credit, bytes)
    handle_info({Tail, records}, state)
  end

  def handle_info(:tail_overloaded, state), do: {:stop, :normal, {1013, "tail backlog limit"}, state}

  def handle_info({Tail, records}, state) do
    {:message_queue_len, backlog} = Process.info(self(), :message_queue_len)

    if backlog > state.max_backlog do
      {:push, {:text, frame([], dropped(records))}, state}
    else
      case Tail.select(state.compiled, records) do
        [] -> {:ok, state}
        entries -> {:push, entries |> Enum.chunk_every(state.limit) |> Enum.map(&{:text, frame(&1, [])}), state}
      end
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{follower: pid} = state) do
    {:stop, :normal, {1013, "tail follower unavailable"}, state}
  end

  def handle_info(:ping, state) do
    schedule_ping()
    {:push, {:ping, ""}, state}
  end

  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def terminate(_reason, state) do
    Tail.leave(state.tenant)
  end

  defp schedule_ping, do: Process.send_after(self(), :ping, @ping_interval_ms)

  defp dropped(records) do
    records
    |> Enum.take(@max_dropped_reported)
    |> Enum.map(fn %Log{} = record ->
      entry = Entry.from_record(record)
      %{"labels" => entry.labels, "timestamp" => Integer.to_string(entry.timestamp_ns || 0)}
    end)
  end

  @doc false
  @spec frame([Entry.t()], [map()]) :: binary()
  def frame(entries, dropped) do
    streams =
      entries
      |> Enum.group_by(& &1.labels)
      |> Enum.map(fn {labels, group} ->
        %{
          "stream" => labels,
          "values" => Enum.map(group, &[Integer.to_string(&1.timestamp_ns || 0), &1.line])
        }
      end)

    Pulse.JSON.encode!(%{"streams" => streams, "dropped_entries" => if(dropped != [], do: dropped)})
  end
end
