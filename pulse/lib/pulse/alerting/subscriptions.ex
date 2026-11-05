defmodule Pulse.Alerting.Subscriptions do
  @moduledoc "Bounded request-scoped MCP subscriptions; durable replay remains in object storage."
  alias Pulse.Alerting.{Principal, Resources}
  alias Pulse.Alerting.SubscriptionSlots

  @registry SubscriptionSlots
  @global_limit 64
  @principal_limit 2
  @interval 1000
  @duration 600_000

  def child_spec(_opts), do: Registry.child_spec(keys: :unique, name: @registry)

  def prepare(conn, requested) when is_list(requested) and length(requested) <= 32 do
    uris = requested |> Enum.filter(&match?({:ok, _, _, _}, Resources.parse(&1))) |> Enum.uniq()

    with {:ok, actors} <- actors(conn, uris), {:ok, fingerprints} <- fingerprints(conn, uris) do
      {:ok,
       %{
         conn: credential_conn(conn),
         uris: uris,
         actors: actors,
         fingerprints: fingerprints,
         started: System.monotonic_time(:millisecond)
       }}
    end
  end

  def prepare(_, _), do: {:error, :invalid_subscription}

  def acquire(%{actors: actors}) do
    identity = actors |> Enum.map(fn {tenant, actor} -> {tenant, actor.id} end) |> Enum.sort()

    with {:ok, principal_key} <- slot({:principal, identity}, @principal_limit) do
      case slot(:global, @global_limit) do
        {:ok, global_key} ->
          {:ok, [global_key, principal_key]}

        error ->
          Registry.unregister(@registry, principal_key)
          error
      end
    end
  end

  def release(keys), do: Enum.each(keys, &Registry.unregister(@registry, &1))

  def poll(subscription) do
    with true <- System.monotonic_time(:millisecond) - subscription.started < @duration,
         {:ok, current} <- actors(subscription.conn, subscription.uris),
         true <- current == subscription.actors,
         {:ok, fingerprints} <- fingerprints(subscription.conn, subscription.uris) do
      changed = Enum.filter(subscription.uris, &(fingerprints[&1] != subscription.fingerprints[&1]))
      {:ok, changed, %{subscription | fingerprints: fingerprints}}
    else
      _ -> :complete
    end
  end

  def interval, do: @interval

  defp slot(scope, limit), do: register_slot(scope, 0, limit)
  defp register_slot(_scope, index, limit) when index == limit, do: {:error, :subscription_overloaded}

  defp register_slot(scope, index, limit) do
    key = {scope, index}

    case Registry.register(@registry, key, nil) do
      {:ok, _} -> {:ok, key}
      {:error, {:already_registered, _}} -> register_slot(scope, index + 1, limit)
    end
  end

  defp actors(conn, uris), do: Enum.reduce_while(uris, {:ok, %{}}, &actor(conn, &1, &2))

  defp actor(conn, uri, {:ok, acc}) do
    with {:ok, tenant, _id, _kind} <- Resources.parse(uri),
         {:ok, actor} <- Principal.authenticate(conn, tenant) do
      {:cont, {:ok, Map.put(acc, tenant, actor)}}
    else
      error -> {:halt, error}
    end
  end

  defp fingerprints(conn, uris), do: Enum.reduce_while(uris, {:ok, %{}}, &fingerprint(conn, &1, &2))

  defp fingerprint(conn, uri, {:ok, acc}) do
    case Resources.fingerprint(conn, uri) do
      {:ok, digest} -> {:cont, {:ok, Map.put(acc, uri, digest)}}
      error -> {:halt, error}
    end
  end

  defp credential_conn(conn) do
    headers = Plug.Conn.get_req_header(conn, "authorization") |> Enum.map(&{"authorization", :binary.copy(&1)})
    %Plug.Conn{req_headers: headers}
  end
end
