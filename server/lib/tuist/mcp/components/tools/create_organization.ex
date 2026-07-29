defmodule Tuist.MCP.Components.Tools.CreateOrganization do
  @moduledoc """
  Create a Tuist organization for the authenticated user.
  """

  use Tuist.MCP.Tool,
    name: "create_organization",
    title: "Create Organization",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "properties" => %{
        "handle" => %{
          "type" => "string",
          "description" => "The organization handle to create."
        }
      },
      "required" => ["handle"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "integer"},
        "name" => %{"type" => "string"},
        "account_handle" => %{"type" => "string"}
      },
      "required" => ["id", "name", "account_handle"],
      "additionalProperties" => false
    }

  alias Tuist.Accounts
  alias Tuist.MCP.Formatter

  @impl EMCP.Tool
  def description, do: "Create a Tuist organization for the authenticated user."

  def execute(%{assigns: %{current_user: user}}, %{"handle" => handle}) when is_binary(handle) do
    case Accounts.create_organization(%{name: handle, creator: user}) do
      {:ok, organization} ->
        Tuist.Analytics.organization_create(handle, user)

        {:ok,
         %{
           id: organization.id,
           name: organization.account.name,
           account_handle: organization.account.name
         }}

      {:error, changeset} ->
        {:error, Formatter.changeset_errors(changeset)}
    end
  end

  def execute(_conn, _args), do: {:error, "You must authenticate as a user to create organizations."}
end
