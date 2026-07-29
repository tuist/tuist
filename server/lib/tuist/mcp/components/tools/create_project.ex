defmodule Tuist.MCP.Components.Tools.CreateProject do
  @moduledoc """
  Create a Tuist project under an account the authenticated user can access.
  """

  use Tuist.MCP.Tool,
    name: "create_project",
    title: "Create Project",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{
          "type" => "string",
          "description" => "The account or organization handle that will own the project."
        },
        "project_handle" => %{
          "type" => "string",
          "description" => "The project handle to create."
        },
        "build_system" => %{
          "type" => "string",
          "enum" => ["xcode", "gradle"],
          "description" => "The project's build system. Defaults to xcode."
        }
      },
      "required" => ["account_handle", "project_handle"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "integer"},
        "name" => %{"type" => "string"},
        "account_handle" => %{"type" => "string"},
        "full_handle" => %{"type" => "string"},
        "build_system" => %{"type" => "string", "enum" => ["xcode", "gradle"]},
        "default_branch" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "name",
        "account_handle",
        "full_handle",
        "build_system",
        "default_branch"
      ],
      "additionalProperties" => false
    }

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.MCP.Formatter
  alias Tuist.Projects

  @impl EMCP.Tool
  def description, do: "Create a Tuist project under an account the authenticated user can access."

  def execute(
        %{assigns: %{current_user: user}},
        %{"account_handle" => account_handle, "project_handle" => project_handle} = args
      )
      when is_binary(account_handle) and is_binary(project_handle) do
    build_system = Map.get(args, "build_system", "xcode")
    create_project(user, account_handle, project_handle, build_system)
  end

  def execute(_conn, _args), do: {:error, "You must authenticate as a user to create projects."}

  defp create_project(user, account_handle, project_handle, build_system) do
    account = accessible_account(user, account_handle)

    cond do
      is_nil(account) ->
        {:error, not_authorized_error()}

      Authorization.authorize(:project_create, user, account) != :ok ->
        {:error, not_authorized_error()}

      true ->
        case Projects.create_project(%{name: project_handle, account: account},
               build_system: build_system
             ) do
          {:ok, project} ->
            {:ok,
             %{
               id: project.id,
               name: project.name,
               account_handle: account.name,
               full_handle: "#{account.name}/#{project.name}",
               build_system: to_string(project.build_system),
               default_branch: project.default_branch
             }}

          {:error, changeset} ->
            {:error, Formatter.changeset_errors(changeset)}
        end
    end
  end

  defp accessible_account(user, account_handle) do
    own_account = Accounts.get_account_from_user(user)

    organization_accounts =
      user
      |> Accounts.get_user_organization_accounts()
      |> Enum.map(& &1.account)

    [own_account | organization_accounts]
    |> Enum.reject(&is_nil/1)
    |> Enum.find(&(&1.name == account_handle))
  end

  defp not_authorized_error, do: "The authenticated subject is not authorized to perform this action."
end
