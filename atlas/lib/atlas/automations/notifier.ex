defmodule Atlas.Automations.Notifier do
  @moduledoc "Post-commit, cross-replica invalidations over the existing Oban notifier."
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def topic(id), do: "automation:#{id}"

  # Postgres NOTIFY is committed with the event's transaction. The test PG
  # notifier is deliberately excluded because it sends before commit.
  def changed(id) do
    if match?({Oban.Notifiers.Postgres, _}, Oban.config().notifier) do
      Oban.Notifier.notify(:automation, %{run_id: id})
    end

    :ok
  end

  @impl true
  def init(_) do
    :ok = Oban.Notifier.listen(:automation)
    {:ok, nil}
  end

  @impl true
  def handle_info({:notification, :automation, %{"run_id" => id}}, state) when is_binary(id) do
    Phoenix.PubSub.broadcast(Atlas.PubSub, topic(id), :automation_changed)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}
end
