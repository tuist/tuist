defmodule Atlas.MCP.Tools.CreateContact do
  @moduledoc """
  Adds a contact to an account.
  """

  use Atlas.MCP.Tool,
    name: "create_contact",
    schema: %{
      "type" => "object",
      "required" => ["full_name"],
      "properties" =>
        Map.merge(Atlas.MCP.AccountLookup.identifier_schema_properties(), %{
          "full_name" => %{"type" => "string"},
          "email" => %{"type" => "string", "format" => "email"},
          "linkedin_url" => %{"type" => "string", "format" => "uri"},
          "title" => %{"type" => "string"},
          "notes" => %{"type" => "string"}
        })
    },
    output_schema: Atlas.MCP.Serializers.Accounts.contact_schema()

  alias Atlas.Accounts
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Add a contact to an account."

  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args) do
      attrs = Map.take(args, ["full_name", "email", "title", "notes", "linkedin_url"])

      case Accounts.create_contact(account, attrs) do
        {:ok, contact} -> {:ok, AccountSerializer.contact(contact)}
        {:error, changeset} -> {:error, "Could not create contact: #{Tool.format_changeset_errors(changeset)}"}
      end
    end
  end
end
