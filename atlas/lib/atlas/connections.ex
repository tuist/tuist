defmodule Atlas.Connections do
  @moduledoc """
  Personal OAuth grants, separate from Atlas sign-in and shared integration credentials.
  Only trusted server-side consumers should call `access_token/2`; tokens must never
  be returned by a LiveView, MCP tool, or included in an agent prompt.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Connections.Authorization
  alias Atlas.Connections.Connection
  alias Atlas.Connections.Provider
  alias Atlas.Repo
  alias Atlas.Users.User

  # Signed-cookie deletion alone cannot stop replay of an old cookie. Consume
  # the hashed provider nonce atomically in PostgreSQL before any token exchange.
  def begin_authorization(%User{} = user, provider, nonce) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    Repo.delete_all(from a in Authorization, where: a.expires_at <= ^now)

    Repo.insert(%Authorization{
      nonce_hash: :crypto.hash(:sha256, nonce),
      user_id: user.id,
      provider: provider,
      expires_at: DateTime.add(now, 600, :second)
    })
  end

  def consume_authorization(user_id, provider, nonce) do
    hash = :crypto.hash(:sha256, nonce)
    now = DateTime.utc_now()

    query =
      from a in Authorization,
        where: a.nonce_hash == ^hash and a.user_id == ^user_id and a.provider == ^provider and a.expires_at > ^now

    case Repo.delete_all(query) do
      {1, _} -> :ok
      _ -> {:error, :invalid_state}
    end
  end

  def list(%User{} = user) do
    connections = Repo.all(from c in Connection, where: c.user_id == ^user.id)

    Enum.map(Provider.providers(), fn provider ->
      {:ok, config} = Provider.config(provider)
      connection = Enum.find(connections, &(&1.provider == provider))

      %{
        provider: provider,
        name: config.name,
        configured: Provider.configured?(provider),
        account_name: connection && connection.account_name,
        scopes: if(connection, do: connection.scopes, else: []),
        status: status(connection)
      }
    end)
  end

  def connect(%User{} = user, provider, code, redirect_uri, verifier) do
    with {:ok, attrs} <- Provider.exchange(provider, code, redirect_uri, verifier),
         {:ok, connection} <- save(user, provider, attrs) do
      audit("connection.connected", connection, user)
      {:ok, connection}
    end
  end

  def disconnect(%User{} = user, provider) when provider in ~w(github slack google) do
    # Serialize with refresh so a rotating token cannot resurrect a disconnected grant.
    Repo.transaction(fn ->
      case locked_connection(user, provider) do
        nil ->
          :ok

        connection ->
          Repo.delete!(connection)
          audit("connection.disconnected", connection, user)
          :ok
      end
    end)
  end

  def disconnect(%User{}, _provider), do: {:error, :unsupported_provider}

  def authorized?(%User{} = user, provider, scopes) do
    now = DateTime.add(DateTime.utc_now(), 120, :second)

    Repo.exists?(
      from c in Connection,
        where: c.user_id == ^user.id and c.provider == ^provider and not c.needs_authorization,
        where: fragment("? && ?", c.scopes, ^scopes),
        where: is_nil(c.expires_at) or c.expires_at > ^now or not is_nil(c.refresh_token)
    )
  end

  def access_token(%User{} = user, provider, scopes \\ []) do
    # Providers can rotate refresh tokens; serialize consumers on the latest row.
    Repo.transaction(fn ->
      with {:ok, connection} <- usable_connection(locked_connection(user, provider), user) do
        if scopes == [] or Enum.any?(scopes, &(&1 in connection.scopes)),
          do: {:ok, connection.access_token},
          else: {:error, :insufficient_scope}
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp usable_connection(nil, _user), do: {:error, :not_connected}
  defp usable_connection(%Connection{needs_authorization: true}, _user), do: {:error, :needs_authorization}

  defp usable_connection(connection, user) do
    if Connection.expired?(connection) do
      refresh(connection, user)
    else
      {:ok, connection}
    end
  end

  defp refresh(%Connection{refresh_token: nil} = connection, user), do: needs_authorization(connection, user)

  defp refresh(connection, user) do
    case Provider.refresh(connection.provider, connection.refresh_token) do
      {:ok, attrs} ->
        attrs =
          attrs
          |> Map.update!(:refresh_token, &(&1 || connection.refresh_token))
          |> Map.update!(:scopes, fn scopes -> if scopes == [], do: connection.scopes, else: scopes end)

        updated = connection |> Connection.changeset(attrs) |> Repo.update!()
        audit("connection.refreshed", updated, user)
        {:ok, updated}

      {:error, :needs_authorization} ->
        needs_authorization(connection, user)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp needs_authorization(connection, user) do
    connection |> Ecto.Changeset.change(needs_authorization: true) |> Repo.update!()
    audit("connection.needs_authorization", connection, user)
    {:error, :needs_authorization}
  end

  defp locked_connection(user, provider) do
    Repo.one(from c in Connection, where: c.user_id == ^user.id and c.provider == ^provider, lock: "FOR UPDATE")
  end

  defp save(user, provider, attrs) do
    Repo.transaction(fn ->
      existing = locked_connection(user, provider)

      # Do not carry a refresh token across a reconnect to a different external account.
      attrs =
        if existing && existing.provider_user_id == attrs.provider_user_id &&
             existing.workspace_id == attrs.workspace_id do
          Map.update!(attrs, :refresh_token, &(&1 || existing.refresh_token))
        else
          attrs
        end

      changeset =
        (existing || %Connection{user_id: user.id, provider: provider})
        |> Connection.changeset(attrs)

      case Repo.insert_or_update(changeset) do
        {:ok, connection} -> connection
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp status(nil), do: "not_connected"
  defp status(%Connection{needs_authorization: true}), do: "needs_authorization"

  defp status(connection) do
    if Connection.expired?(connection) && is_nil(connection.refresh_token),
      do: "needs_authorization",
      else: "connected"
  end

  defp audit(action, connection, user) do
    Audit.record(
      action,
      %{
        target_type: "user_connection",
        target_id: connection.id,
        target_label: connection.provider,
        metadata: %{"provider" => connection.provider, "dashboard_path" => "/settings/connections"}
      },
      actor: user
    )
  end
end
