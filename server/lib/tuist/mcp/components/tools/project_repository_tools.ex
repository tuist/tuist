defmodule Tuist.MCP.Components.Tools.ConnectProjectRepository do
  @moduledoc """
  Link a project to a GitHub repository its account's GitHub App installation
  can access.
  """

  use Tuist.MCP.Tool,
    name: "connect_project_repository",
    title: "Connect Project Repository",
    read_only_hint: false,
    destructive_hint: false,
    authorize: [action: :update, category: :project],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{
          "type" => "string",
          "description" => "The account or organization handle that owns the project."
        },
        "project_handle" => %{
          "type" => "string",
          "description" => "The project handle."
        },
        "repository_full_handle" => %{
          "type" => "string",
          "pattern" => "^[\\w\\-\\.]+/[\\w\\-\\.]+$",
          "description" => "The repository's full handle, in the format owner/name."
        }
      },
      "required" => ["account_handle", "project_handle", "repository_full_handle"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "provider" => %{"type" => "string", "enum" => ["github", "origin"]},
        "repository_full_handle" => %{"type" => "string"}
      },
      "required" => ["provider", "repository_full_handle"],
      "additionalProperties" => false
    }

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.VCS

  @impl EMCP.Tool
  def description,
    do:
      "Link a project to a GitHub repository so pull request comments, bundle checks, and selective testing work. " <>
        "The account's GitHub App must be installed and able to access the repository; the project adopts the " <>
        "repository's default branch. Linking a project to the repository it is already linked to returns the " <>
        "existing link. Use `disconnect_project_repository` first to link a different repository."

  def execute(conn, %{"repository_full_handle" => handle}, project) do
    case VCS.connect_github_repository(project, handle, created_by_id: actor_id(conn.assigns)) do
      {:ok, connection} ->
        {:ok, %{provider: Atom.to_string(connection.provider), repository_full_handle: connection.repository_full_handle}}

      {:error, {:already_connected, connection}} ->
        {:error,
         "The project is already linked to #{connection.repository_full_handle}. Unlink it with `disconnect_project_repository` before linking another repository."}

      {:error, :github_app_not_installed} ->
        {:error, "The account has no GitHub App installation. Install it from the account's integrations settings."}

      {:error, :repository_not_accessible} ->
        {:error, "The account's GitHub App installation can't access #{handle}."}

      {:error, %Ecto.Changeset{}} ->
        {:error, "The project couldn't be linked to #{handle}."}
    end
  end

  defp actor_id(%{current_user: %User{id: id}}), do: id
  defp actor_id(%{current_subject: %AuthenticatedAccount{issued_by: %User{id: id}}}), do: id
  defp actor_id(_assigns), do: nil
end

defmodule Tuist.MCP.Components.Tools.DisconnectProjectRepository do
  @moduledoc """
  Remove a project's link to its GitHub repository.
  """

  use Tuist.MCP.Tool,
    name: "disconnect_project_repository",
    title: "Disconnect Project Repository",
    read_only_hint: false,
    destructive_hint: true,
    authorize: [action: :update, category: :project],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{
          "type" => "string",
          "description" => "The account or organization handle that owns the project."
        },
        "project_handle" => %{
          "type" => "string",
          "description" => "The project handle."
        }
      },
      "required" => ["account_handle", "project_handle"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"disconnected" => %{"type" => "boolean"}},
      "required" => ["disconnected"],
      "additionalProperties" => false
    }

  alias Tuist.VCS

  @impl EMCP.Tool
  def description,
    do:
      "Remove a project's link to its GitHub repository. Pull request comments, bundle checks, and selective " <>
        "testing stop using the repository until the project is linked again."

  def execute(_conn, _args, project) do
    case VCS.disconnect_github_repository(project) do
      {:ok, _connection} -> {:ok, %{disconnected: true}}
      {:error, :not_found} -> {:error, "The project isn't linked to a GitHub repository."}
    end
  end
end
