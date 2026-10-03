defmodule Atlas.MCP.Tools.ListAccountContacts do
  @moduledoc """
  Lists contacts associated with an account.
  """

  use Atlas.MCP.Tool,
    name: "list_account_contacts",
    schema: %{
      "type" => "object",
      "properties" => Atlas.MCP.AccountLookup.identifier_schema_properties()
    },
    output_schema:
      Atlas.MCP.Serializers.Accounts.list_response_schema(
        :contacts,
        Atlas.MCP.Serializers.Accounts.contact_schema()
      )

  import Ecto.Query

  alias Atlas.Accounts.Contact
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.Repo

  @impl EMCP.Tool
  def description, do: "List contacts for an account."

  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args) do
      contacts =
        Contact
        |> where([c], c.account_id == ^account.id)
        |> order_by([c], asc: c.full_name, asc: c.email)
        |> Repo.all()
        |> Enum.map(&AccountSerializer.contact/1)

      {:ok, AccountSerializer.list_response(:contacts, contacts)}
    end
  end
end
