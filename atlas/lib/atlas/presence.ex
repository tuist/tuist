defmodule Atlas.Presence do
  @moduledoc "Short-lived, replica-independent availability. Locations never leave this context."

  import Ecto.Query

  alias Atlas.Demo
  alias Atlas.Native
  alias Atlas.Presence.Connection
  alias Atlas.Repo
  alias Atlas.Users
  alias Atlas.Users.User

  def sync(%User{} = user, connection_id, params) do
    with false <- Demo.enabled?(),
         {:ok, connection_id} <- Ecto.UUID.cast(connection_id),
         {:ok, location} <- location(user, params) do
      Repo.insert_all(Connection, [%{user_id: user.id, connection_id: connection_id, location: location}],
        conflict_target: [:user_id, :connection_id],
        on_conflict:
          from(c in Connection,
            update: [set: [location: ^location, expires_at: fragment("clock_timestamp() + interval '20 seconds'")]]
          )
      )

      changed()
      {:ok, snapshot(user, location)}
    else
      true -> {:error, :forbidden}
      :error -> {:error, :invalid_params}
      error -> error
    end
  end

  def leave(%User{} = user, connection_id) do
    with false <- Demo.enabled?(),
         {:ok, connection_id} <- Ecto.UUID.cast(connection_id) do
      drop_connection(user.id, connection_id)
    else
      true -> {:error, :forbidden}
      _ -> {:error, :invalid_params}
    end
  end

  def drop_connection(user_id, connection_id) do
    {count, _} =
      Repo.delete_all(from c in Connection, where: c.user_id == ^user_id and c.connection_id == ^connection_id)

    if count > 0, do: changed()
    :ok
  end

  def renew(%User{} = user, connection_id, params) do
    {count, _} =
      Repo.update_all(
        from(c in Connection,
          where: c.user_id == ^user.id and c.connection_id == ^connection_id,
          update: [set: [expires_at: fragment("clock_timestamp() + interval '20 seconds'")]]
        ),
        []
      )

    if count == 0, do: sync(user, connection_id, params)
    :ok
  end

  def subscribe, do: Phoenix.PubSub.subscribe(Atlas.PubSub, "presence")

  defp changed, do: Oban.Notifier.notify(Oban, :atlas_presence, %{})

  def snapshot(%User{} = viewer, location \\ nil) do
    connections =
      Repo.all(
        from c in Connection,
          where: c.expires_at > fragment("clock_timestamp()"),
          select: {c.user_id, c.location}
      )
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    people =
      Enum.map(Users.list_users(), fn user ->
        locations = Map.get(connections, user.id, [])

        %{
          id: user.id,
          name: user.name || user.email,
          email: user.email,
          online: locations != [],
          here: user.id != viewer.id and not is_nil(location) and location in locations
        }
      end)

    %{self_id: viewer.id, people: people}
  end

  def prune do
    {count, _} = Repo.delete_all(from c in Connection, where: c.expires_at <= fragment("clock_timestamp()"))
    if count > 0, do: changed()
    :ok
  end

  def location(user, %{"resource" => resource} = params) when resource in ["tasks", "accounts", "invoices"] do
    scope = %{"accounts" => "accounts:read", "invoices" => "finance:read"}[resource]

    if is_nil(scope) or Users.has_scope?(user, scope) do
      case Map.get(params, "id") do
        nil ->
          {:ok, resource}

        id ->
          case Native.get(resource, id) do
            {:ok, _} -> {:ok, "#{resource}:#{String.downcase(id)}"}
            _ -> {:error, :not_found}
          end
      end
    else
      {:error, :forbidden}
    end
  end

  def location(_user, %{"resource" => resource} = params) when resource in ["people", "time_off", "profile"] do
    if is_nil(params["id"]), do: {:ok, resource}, else: {:error, :invalid_params}
  end

  def location(_user, params) when params == %{}, do: {:ok, nil}
  def location(_user, _params), do: {:error, :invalid_params}

  def page_location(user, path) do
    params = path |> String.split("/", trim: true) |> page_params()

    case location(user, params) do
      {:ok, _} -> params
      _ -> %{}
    end
  end

  defp page_params(["tasks"]), do: %{"resource" => "tasks"}
  defp page_params(["people"]), do: %{"resource" => "people"}
  defp page_params(["people", "time-off"]), do: %{"resource" => "time_off"}
  defp page_params(["commercial", "sales", "accounts"]), do: %{"resource" => "accounts"}
  defp page_params(["commercial", "sales", "accounts", id]), do: %{"resource" => "accounts", "id" => id}
  defp page_params(["commercial", "finance"]), do: %{"resource" => "invoices"}
  defp page_params(["settings"]), do: %{"resource" => "profile"}
  defp page_params(_path), do: %{}
end
