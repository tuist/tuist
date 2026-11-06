defmodule Atlas.Presence.Notifier do
  @moduledoc false
  use GenServer

  alias Atlas.Presence

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ok = Oban.Notifier.listen(Oban, :atlas_presence)
    if Oban.config().testing == :disabled, do: Process.send_after(self(), :sweep, 5_000)
    {:ok, %{sweeps: 0}}
  end

  @impl true
  def handle_info({:notification, :atlas_presence, _payload}, state) do
    broadcast()
    {:noreply, state}
  end

  def handle_info(:sweep, state) do
    Presence.prune()
    # LISTEN/NOTIFY is not replayed after a database outage. Repair missed
    # invalidations without making clients poll snapshots.
    if rem(state.sweeps, 12) == 0, do: broadcast()
    Process.send_after(self(), :sweep, 5_000)
    {:noreply, %{state | sweeps: state.sweeps + 1}}
  end

  defp broadcast, do: Phoenix.PubSub.broadcast(Atlas.PubSub, "presence", :presence_changed)
end
