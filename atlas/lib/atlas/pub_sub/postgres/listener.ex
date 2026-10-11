defmodule Atlas.PubSub.Postgres.Listener do
  @moduledoc false

  @behaviour Postgrex.SimpleConnection

  alias Atlas.PubSub.Postgres
  alias Postgrex.SimpleConnection

  def child_spec(args), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [args]}}
  def start_link({state, opts}), do: SimpleConnection.start_link(__MODULE__, state, opts)

  @impl true
  def init(state), do: {:ok, state}

  # LISTEN is reissued after every reconnect. Topics never become SQL identifiers.
  @impl true
  def handle_connect(state) do
    channel = String.replace(state.channel, "\"", "\"\"")
    {:query, "LISTEN \"#{channel}\"", state}
  end

  @impl true
  def handle_disconnect(state), do: {:noreply, state}

  @impl true
  def handle_result(_results, state), do: {:noreply, state}

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_call(:instance_id, from, state) do
    SimpleConnection.reply(from, state.instance_id)
    {:noreply, state}
  end

  @impl true
  def notify(channel, payload, state), do: Postgres.notify(channel, payload, state)
end
