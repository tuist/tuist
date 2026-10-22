defmodule Atlas.Conversations.Notifier do
  @moduledoc """
  Fans conversation invalidations out to local channel and run processes.

  Producers publish id-only payloads through Oban's PostgreSQL notifier, so
  every replica hears every change without an Erlang mesh. Subscribers always
  reload authoritative state and re-authorize before pushing anything. The
  sweep expires viewer leases and marks runs with a stale heartbeat as
  interrupted; LISTEN/NOTIFY is not durable, so channels also re-read state on
  their own renewal timer.
  """

  use GenServer

  alias Atlas.Conversations
  alias Atlas.Conversations.Runs
  alias Atlas.Conversations.Viewers

  @sweep_interval :timer.seconds(5)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ok = Oban.Notifier.listen(Oban, Conversations.notification_channel())
    if Oban.config().testing == :disabled, do: Process.send_after(self(), :sweep, @sweep_interval)
    {:ok, %{sweeps: 0}}
  end

  @impl true
  def handle_info({:notification, :atlas_conversations, %{"conversation_id" => id}}, state) do
    Phoenix.PubSub.broadcast(Atlas.PubSub, Conversations.topic(id), :conversation_changed)
    # List channels hear an id-free invalidation and recompute their own
    # authorized list, so nothing about other people's conversations leaks.
    Phoenix.PubSub.broadcast(Atlas.PubSub, Conversations.list_topic(), :conversations_changed)
    {:noreply, state}
  end

  def handle_info({:notification, :atlas_conversations, %{"cancel_run_id" => id}}, state) do
    Phoenix.PubSub.broadcast(Atlas.PubSub, Conversations.run_topic(id), :cancel)
    {:noreply, state}
  end

  def handle_info({:notification, _channel, _payload}, state), do: {:noreply, state}

  def handle_info(:sweep, state) do
    Viewers.prune()

    if rem(state.sweeps, 3) == 0 do
      Runs.resume_stale()
      Runs.recover_queued()
    end

    Process.send_after(self(), :sweep, @sweep_interval)
    {:noreply, %{state | sweeps: state.sweeps + 1}}
  end
end
