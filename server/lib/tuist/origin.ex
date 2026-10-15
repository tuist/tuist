defmodule Tuist.Origin do
  @moduledoc """
  Account and repository connections to Cursor Origin.
  """

  import Ecto.Query

  alias Tuist.Authorization
  alias Tuist.Environment
  alias Tuist.Origin.Auth
  alias Tuist.Origin.Client
  alias Tuist.Origin.Installation
  alias Tuist.Projects
  alias Tuist.Projects.VCSConnection
  alias Tuist.Repo

  @scopes ~w(repository:contents:read repository:pull_requests:read repository:pull_requests:reviews:write repository:checks:write)

  def installation_for_account(account_id), do: Repo.get_by(Installation, account_id: account_id)

  def confirm(account, user, pending) do
    with %{"expires_at" => expires_at} <- pending,
         true <- expires_at > System.system_time(:second) do
      connect(account, user, pending)
    else
      _ -> {:error, :expired_installation}
    end
  end

  def pending_installation(receipt) do
    with {:ok, claims} <- Auth.verify_receipt(receipt) do
      {:ok,
       %{
         "installation_id" => claims["sub"],
         "namespace_id" => claims["namespace_id"],
         "expires_at" => claims["exp"],
         "state" => claims["state"]
       }}
    end
  end

  def install_url(state) do
    %{app_id: app_id} = Environment.origin_app_credentials()

    "https://cursor.com/codebase/apps/install?" <>
      URI.encode_query(%{
        client_id: app_id,
        scope: Enum.join(@scopes, " "),
        redirect_uri: Environment.app_url(path: "/integrations/origin/setup"),
        state: state,
        include_granted_scopes: "true"
      })
  end

  def connect(account, user, %{"installation_id" => id, "namespace_id" => namespace_id}) do
    with :ok <- Authorization.authorize(:account_update, user, account),
         {:ok, %{"target" => %{"id" => ^namespace_id}} = remote} <- Client.get_installation(id),
         true <- remote["appId"] == Environment.origin_app_credentials().app_id,
         existing = Repo.get_by(Installation, installation_id: id),
         true <- is_nil(existing) or existing.account_id == account.id do
      installation = existing || %Installation{}

      installation
      |> Installation.changeset(Map.put(installation_attrs(remote), :account_id, account.id))
      |> Repo.insert_or_update()
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_installation}
    end
  end

  def disconnect(account, user) do
    with :ok <- Authorization.authorize(:account_update, user, account),
         %Installation{} = installation <- installation_for_account(account.id),
         {:ok, _} <- delete_remote_installation(installation.installation_id) do
      Repo.delete(installation)
    else
      nil -> {:ok, nil}
      {:error, _} = error -> error
    end
  end

  def connect_project(account, user, project_id, repository_id) do
    with :ok <- Authorization.authorize(:account_update, user, account),
         project when not is_nil(project) <- Repo.get_by(Projects.Project, id: project_id, account_id: account.id),
         %Installation{suspended: false} = installation <- installation_for_account(account.id),
         {:ok, repositories} <- Client.repositories(installation),
         %{"id" => ^repository_id, "fullName" => handle} = repository <-
           Enum.find(repositories, &(&1["id"] == repository_id and is_nil(&1["mirror"]))) do
      Repo.transact(fn ->
        with {:ok, connection} <-
               Projects.create_vcs_connection(%{
                 project_id: project.id,
                 provider: :origin,
                 repository_full_handle: handle,
                 origin_repository_id: repository_id,
                 origin_app_installation_id: installation.id,
                 created_by_id: user.id
               }),
             {:ok, _} <- Projects.update_project(project, %{default_branch: repository["defaultBranch"] || "main"}) do
          {:ok, connection}
        end
      end)
    else
      {:error, _} = error -> error
      _ -> {:error, :repository_not_accessible}
    end
  end

  def handle_webhook(%{"appId" => app_id, "installationId" => id, "event" => %{"type" => type}}) do
    with %{app_id: ^app_id} <- Environment.origin_app_credentials(),
         %Installation{} = installation <- Repo.get_by(Installation, installation_id: id) do
      if String.starts_with?(type, "installation.") do
        reconcile_installation(installation)
      else
        :ok
      end
    else
      nil -> :ok
      _ -> {:error, :invalid_app}
    end
  end

  def handle_webhook(%{"appId" => app_id, "event" => %{"type" => "ping"}}) do
    case Environment.origin_app_credentials() do
      %{app_id: ^app_id} -> :ok
      _ -> {:error, :invalid_app}
    end
  end

  def handle_webhook(_), do: {:error, :invalid_envelope}

  defp reconcile_installation(installation) do
    case Client.get_installation(installation.installation_id) do
      {:ok, remote} ->
        with {:ok, current} <- installation |> Installation.changeset(installation_attrs(remote)) |> Repo.update() do
          reconcile_repositories(current)
        end

      {:error, {:http, 404}} ->
        case Repo.delete(installation) do
          {:ok, _} -> :ok
          error -> error
        end

      error ->
        error
    end
  end

  defp reconcile_repositories(%{suspended: true}), do: :ok

  defp reconcile_repositories(installation) do
    with {:ok, repositories} <- Client.repositories(installation) do
      repositories = Enum.reject(repositories, &(not is_nil(&1["mirror"])))
      allowed_ids = Enum.map(repositories, & &1["id"])

      Repo.delete_all(
        from(c in VCSConnection,
          where: c.origin_app_installation_id == ^installation.id and c.origin_repository_id not in ^allowed_ids
        )
      )

      # A stable repository ID survives namespace/repository renames.
      connections = Repo.all(from(c in VCSConnection, where: c.origin_app_installation_id == ^installation.id))
      handles = Map.new(repositories, &{&1["id"], &1["fullName"]})
      changed = Enum.filter(connections, &(&1.repository_full_handle != handles[&1.origin_repository_id]))

      if changed != [] do
        Repo.insert_all(
          VCSConnection,
          Enum.map(changed, fn c ->
            %{
              id: c.id,
              project_id: c.project_id,
              provider: :origin,
              origin_app_installation_id: installation.id,
              origin_repository_id: c.origin_repository_id,
              repository_full_handle: handles[c.origin_repository_id],
              inserted_at: c.inserted_at,
              updated_at: DateTime.utc_now(:second)
            }
          end),
          on_conflict: {:replace, [:repository_full_handle, :updated_at]},
          conflict_target: [:id]
        )
      end

      :ok
    end
  end

  defp installation_attrs(remote) do
    %{
      installation_id: remote["id"],
      namespace_id: remote["target"]["id"],
      namespace_slug: remote["target"]["slug"],
      scopes: remote["scopes"] || [],
      suspended: not is_nil(remote["suspendedAt"])
    }
  end

  defp delete_remote_installation(id) do
    case Client.delete_installation(id) do
      {:error, {:http, 404}} -> {:ok, nil}
      result -> result
    end
  end
end
