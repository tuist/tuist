defmodule Atlas.MCP.Tools.ListAccountIncidentContacts do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "list_account_incident_contacts",
    schema: %{
      "type" => "object",
      "description" => "Provide one of account_id, account_key, or handle.",
      "properties" => Atlas.MCP.AccountLookup.identifier_schema_properties()
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "account" => Atlas.MCP.Serializers.Accounts.related_account_schema(),
        "incident_contacts" => %{
          "type" => "array",
          "items" => Atlas.MCP.Serializers.Accounts.incident_contact_schema()
        },
        "count" => %{"type" => "integer"}
      },
      "required" => ["account", "incident_contacts", "count"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer

  @impl EMCP.Tool
  def description do
    "List security-incident notification contacts extracted from an account's contracts, including source document references."
  end

  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args) do
      contacts =
        account
        |> Accounts.list_incident_contacts()
        |> Enum.map(&AccountSerializer.incident_contact/1)

      {:ok,
       %{
         account: AccountSerializer.related_account(account),
         incident_contacts: contacts,
         count: length(contacts)
       }}
    end
  end
end
