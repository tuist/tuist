defmodule Tuist.Origin do
  @moduledoc "Account-scoped Origin installations and project connections."
  import Ecto.Query

  alias Tuist.Authorization
  alias Tuist.Environment
  alias Tuist.Origin.Client
  alias Tuist.Origin.Installation
  alias Tuist.Projects
  alias Tuist.Repo

  def list_installations(account_id) do
    case Environment.origin_app_id() do
      app_id when is_binary(app_id) and app_id != "" ->
        Repo.all(
          from i in Installation,
            where: i.account_id == ^account_id and i.app_id == ^app_id,
            order_by: [asc: i.inserted_at, asc: i.id]
        )

      _ ->
        []
    end
  end

  def attach_installation(account, claims) do
    with {:ok, snapshot} <- Client.get_installation(claims["sub"]),
         :ok <- validate_installation(snapshot),
         true <- get_in(snapshot, ["target", "id"]) == claims["namespace_id"],
         {:ok, _} <-
           %Installation{}
           |> Installation.changeset(%{
             account_id: account.id,
             app_id: snapshot["appId"],
             installation_id: snapshot["id"],
             namespace_id: claims["namespace_id"]
           })
           |> Repo.insert(on_conflict: :nothing, conflict_target: [:app_id, :installation_id]),
         %Installation{account_id: account_id} = installation <-
           Repo.get_by(Installation, app_id: snapshot["appId"], installation_id: snapshot["id"]),
         true <- account_id == account.id do
      {:ok, installation}
    else
      false -> {:error, :installation_already_connected}
      {:error, _} = error -> error
      _ -> {:error, :invalid_origin_installation}
    end
  end

  def installation_details(account, user, installation_id) do
    with :ok <- Authorization.authorize(:account_update, user, account),
         app_id when is_binary(app_id) and app_id != "" <- Environment.origin_app_id(),
         {:ok, installation_id} <- Ecto.UUID.cast(installation_id),
         %Installation{} = installation <-
           Repo.get_by(Installation,
             id: installation_id,
             account_id: account.id,
             app_id: app_id
           ),
         {:ok, snapshot} <- Client.get_installation(installation.installation_id),
         :ok <- validate_installation(snapshot),
         {:ok, repositories} <- Client.list_repositories(installation) do
      repositories =
        repositories
        |> Enum.filter(&(is_binary(&1["fullName"]) and &1["fullName"] != "" and is_nil(&1["mirror"])))
        |> Enum.map(&%{full_name: &1["fullName"], default_branch: &1["defaultBranch"]})
        |> Enum.sort_by(& &1.full_name)

      {:ok, %{namespace: get_in(snapshot, ["target", "slug"]), repositories: repositories}}
    else
      {:error, _} = error -> error
      _ -> {:error, :not_found}
    end
  end

  def connect_project(account, user, installation_id, project_id, handle)
      when is_binary(installation_id) and (is_binary(project_id) or is_integer(project_id)) and is_binary(handle) do
    with :ok <- Authorization.authorize(:account_update, user, account),
         {:ok, installation_id} <- Ecto.UUID.cast(installation_id),
         {project_id, ""} <- Integer.parse(to_string(project_id)),
         %Installation{} = installation <-
           Repo.get_by(Installation, id: installation_id, account_id: account.id),
         project when not is_nil(project) <- Projects.get_project_by_id(project_id),
         true <- project.account_id == account.id,
         {:ok, snapshot} <- Client.get_installation(installation.installation_id),
         :ok <- validate_installation(snapshot),
         {:ok, repository} <- Client.get_repository(installation, handle),
         true <- is_nil(repository["mirror"]),
         {:ok, connection} <-
           Projects.create_vcs_connection(%{
             provider: :origin,
             repository_full_handle: handle,
             project_id: project.id,
             created_by_id: user.id,
             origin_app_installation_id: installation.id
           }) do
      if is_binary(repository["defaultBranch"]) and repository["defaultBranch"] != "" do
        Projects.update_project(project, %{default_branch: repository["defaultBranch"]})
      end

      {:ok, connection}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_origin_connection}
    end
  end

  def connect_project(_account, _user, _installation_id, _project_id, _handle), do: {:error, :invalid_origin_connection}

  def disconnect(account, user, id) do
    with :ok <- Authorization.authorize(:account_update, user, account),
         {:ok, id} <- Ecto.UUID.cast(id),
         %Installation{} = installation <-
           Repo.get_by(Installation, id: id, account_id: account.id) do
      Repo.delete(installation)
    else
      _ -> {:error, :not_found}
    end
  end

  def installation_for_repository(project, handle) do
    project = Repo.preload(project, vcs_connection: :origin_app_installation)

    with %{
           vcs_connection: %{
             provider: :origin,
             repository_full_handle: connected,
             origin_app_installation: %Installation{} = installation
           }
         } <- project,
         true <- installation.account_id == project.account_id,
         true <- installation.app_id == Environment.origin_app_id(),
         true <- String.downcase(connected) == String.downcase(handle) do
      {:ok, installation}
    else
      _ -> {:error, :not_found}
    end
  end

  def reconcile_installation(installation_id) do
    case Client.get_installation(installation_id) do
      {:ok, _} ->
        :ok

      {:error, {:origin_http_error, 404}} ->
        Repo.delete_all(
          from i in Installation,
            where: i.installation_id == ^installation_id and i.app_id == ^Environment.origin_app_id()
        )

        :ok

      {:error, _} = error ->
        error
    end
  end

  defp validate_installation(snapshot) do
    if snapshot["appId"] == Environment.origin_app_id() and snapshot["suspendedAt"] in [nil, ""] and
         Enum.all?(Client.scopes(), &(&1 in (snapshot["scopes"] || []))) do
      :ok
    else
      {:error, :inactive_origin_installation}
    end
  end
end
