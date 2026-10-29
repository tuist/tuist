defmodule Atlas.MCP.Tools.UpdateContact do
  @moduledoc """
  Updates an existing contact's editable fields.
  """

  use Atlas.MCP.Tool,
    name: "update_contact",
    schema: %{
      "type" => "object",
      "required" => ["contact_id"],
      "properties" => %{
        "contact_id" => %{"type" => "string"},
        "full_name" => %{"type" => "string"},
        "email" => %{"type" => "string", "format" => "email"},
        "linkedin_url" => %{"type" => "string", "format" => "uri"},
        "title" => %{"type" => "string"},
        "notes" => %{"type" => "string"}
      }
    },
    output_schema: Atlas.MCP.Serializers.Accounts.contact_schema()

  alias Atlas.Accounts
  alias Atlas.Accounts.Contact
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Repo

  @impl EMCP.Tool
  def description, do: "Update a contact's full_name, email, title, or notes."

  def execute(_conn, %{"contact_id" => id} = args) when is_binary(id) do
    case Repo.get(Contact, id) do
      nil ->
        {:error, "Contact not found: #{id}"}

      contact ->
        attrs = Map.take(args, ["full_name", "email", "title", "notes", "linkedin_url"])

        case Accounts.update_contact(contact, attrs) do
          {:ok, updated} ->
            {:ok, AccountSerializer.contact(updated)}

          {:error, changeset} ->
            {:error, "Could not update contact: #{Tool.format_changeset_errors(changeset)}"}
        end
    end
  end

  def execute(_conn, _args), do: {:error, "contact_id is required."}
end
