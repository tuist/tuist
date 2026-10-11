defmodule Atlas.PubSub.Postgres do
  @moduledoc """
  PostgreSQL-backed Phoenix PubSub without Distributed Erlang.

  One LISTEN connection per replica fans notifications into its local PubSub.
  Notifications are ephemeral invalidations, not durable work: PostgreSQL and
  Oban remain the sources of truth. A direct/session-pooled database connection
  is required; transaction-mode PgBouncer cannot carry LISTEN subscriptions.
  """

  @behaviour Phoenix.PubSub.Adapter

  use Supervisor

  alias Atlas.PubSub.Postgres.Listener
  alias Atlas.Repo

  require Logger

  @channel "atlas_pubsub"
  @max_payload_bytes 7_999
  @wire_version 1

  @impl true
  def child_spec(opts) do
    %{id: Keyword.fetch!(opts, :adapter_name), start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :adapter_name))

  @impl true
  def init(opts) do
    adapter_name = Keyword.fetch!(opts, :adapter_name)

    state = %{
      pubsub: Keyword.fetch!(opts, :name),
      instance_id: Base.encode16(:crypto.strong_rand_bytes(16)),
      channel: Keyword.get(opts, :channel, @channel)
    }

    # Immutable routing metadata belongs to the adapter supervisor, not the
    # socket process that may block during connection/ping or restart.
    :ets.new(adapter_name, [:named_table, :protected, read_concurrency: true])
    :ets.insert(adapter_name, {:identity, state.instance_id, state.channel})

    connection_opts = Repo.config() |> Keyword.delete(:name) |> Keyword.put(:auto_reconnect, true)
    Supervisor.init([{Listener, {state, connection_opts}}], strategy: :one_for_one)
  end

  @impl true
  def node_name(adapter_name) do
    case identity(adapter_name) do
      {:ok, {instance_id, _channel}} -> instance_id
      {:error, _reason} -> :undefined
    end
  end

  @impl true
  def broadcast(adapter_name, topic, message, dispatcher) do
    publish(adapter_name, nil, topic, message, dispatcher)
  end

  @impl true
  def direct_broadcast(adapter_name, target, topic, message, dispatcher) do
    publish(adapter_name, target, topic, message, dispatcher)
  end

  defp publish(adapter_name, target, topic, message, dispatcher) do
    case identity(adapter_name) do
      {:ok, {source, channel}} ->
        payload =
          {@wire_version, source, target, topic, message, dispatcher} |> :erlang.term_to_binary() |> Base.encode64()

        if byte_size(payload) <= @max_payload_bytes do
          publish_notification(channel, payload)
        else
          {:error, :notification_too_large}
        end

      {:error, _reason} ->
        publication_failed()
    end
  end

  defp identity(adapter_name) do
    case :ets.lookup(adapter_name, :identity) do
      [{:identity, instance_id, channel}] -> {:ok, {instance_id, channel}}
      [] -> {:error, :adapter_unavailable}
    end
  rescue
    ArgumentError -> {:error, :adapter_unavailable}
  end

  defp publish_notification(channel, payload) do
    case Repo.query("SELECT pg_notify($1, $2)", [channel, payload]) do
      {:ok, _result} -> :ok
      {:error, _reason} -> publication_failed()
    end
  rescue
    _error -> publication_failed()
  catch
    :exit, _reason -> publication_failed()
  end

  defp publication_failed do
    # Never log the exception, query parameters, or notification contents.
    Logger.warning("Atlas PubSub remote publication failed; local delivery only")
    :ok
  end

  def notify(channel, payload, %{channel: channel} = state) do
    with {:ok, binary} <- Base.decode64(payload),
         {@wire_version, source, target, topic, message, dispatcher}
         when is_binary(source) and (is_nil(target) or is_binary(target)) and is_binary(topic) and is_atom(dispatcher) <-
           :erlang.binary_to_term(binary, [:safe]),
         true <- valid_dispatcher?(dispatcher),
         true <- deliver?(source, target, state.instance_id) do
      Phoenix.PubSub.local_broadcast(state.pubsub, topic, message, dispatcher)
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  def notify(_channel, _payload, _state), do: :ok

  defp valid_dispatcher?(nil), do: true

  defp valid_dispatcher?(dispatcher),
    do: Code.ensure_loaded?(dispatcher) and function_exported?(dispatcher, :dispatch, 3)

  defp deliver?(source, nil, instance_id), do: source != instance_id
  defp deliver?(_source, target, instance_id), do: target == instance_id
end
