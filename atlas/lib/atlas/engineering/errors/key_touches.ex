defmodule Atlas.Engineering.Errors.KeyTouches do
  @moduledoc """
  Coalesces `errors_project_keys.last_used_at` updates.

  The value backs the "last used" column on the DSN admin surface — a
  UI convenience, not a security or authorization signal — so a small
  batching lag is fine. Every accepted envelope request casts the key
  id here (non-blocking); the GenServer flushes the accumulated set
  every `@flush_interval_ms` with a single `UPDATE ... WHERE id IN
  (...)`. Coalesces N writes-per-second down to at most one every few
  seconds, freeing a Postgres pool slot per request.

  On shutdown the pending set is flushed via `terminate/2` so we don't
  drop the last window.
  """

  use GenServer

  import Ecto.Query

  alias Atlas.Engineering.Errors.ProjectKey
  alias Atlas.Repo

  require Logger

  @flush_interval_ms :timer.seconds(30)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def touch(key_id) when is_binary(key_id) do
    GenServer.cast(__MODULE__, {:touch, key_id})
  end

  def touch(_), do: :ok

  @doc """
  Forces an immediate flush of the pending set. Only used in tests.
  """
  def flush(server \\ __MODULE__) do
    GenServer.call(server, :flush, :infinity)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    interval = Keyword.get(opts, :flush_interval_ms, @flush_interval_ms)
    timer = Process.send_after(self(), :tick, interval)
    {:ok, %{pending: MapSet.new(), timer: timer, interval: interval}}
  end

  @impl true
  def handle_cast({:touch, key_id}, state) do
    {:noreply, %{state | pending: MapSet.put(state.pending, key_id)}}
  end

  @impl true
  def handle_info(:tick, state) do
    do_flush(state.pending)
    timer = Process.send_after(self(), :tick, state.interval)
    {:noreply, %{state | pending: MapSet.new(), timer: timer}}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    Process.cancel_timer(state.timer)
    do_flush(state.pending)
    timer = Process.send_after(self(), :tick, state.interval)
    {:reply, :ok, %{state | pending: MapSet.new(), timer: timer}}
  end

  @impl true
  def terminate(_reason, %{pending: pending}) do
    do_flush(pending)
  end

  defp do_flush(pending) do
    ids = MapSet.to_list(pending)

    case ids do
      [] ->
        :ok

      _ ->
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

        try do
          {_count, _} =
            ProjectKey
            |> where([k], k.id in ^ids)
            |> Repo.update_all(set: [last_used_at: now])

          :ok
        rescue
          error ->
            Logger.warning("errors.key_touches: flush failed for #{length(ids)} key(s): #{Exception.message(error)}")

            :ok
        end
    end
  end
end
