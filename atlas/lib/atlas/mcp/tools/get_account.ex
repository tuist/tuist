defmodule Atlas.MCP.Tools.GetAccount do
  @moduledoc """
  Returns the full account context bundle: core, legal, billing, signatory,
  commercial term, recent event, account attention, contact, handle, revenue, and
  overview summary fields.
  """

  use Atlas.MCP.Tool,
    name: "get_account",
    schema: %{
      "type" => "object",
      "description" => "Provide one of account_id, account_key, or handle.",
      "properties" => Atlas.MCP.AccountLookup.identifier_schema_properties()
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "account" => Atlas.MCP.Serializers.Accounts.account_schema(),
        "contacts" => %{"type" => "array", "items" => Atlas.MCP.Serializers.Accounts.contact_schema()},
        "handles" => %{"type" => "array", "items" => Atlas.MCP.Serializers.Accounts.handle_schema()},
        "terms" => %{"type" => "array", "items" => Atlas.MCP.Serializers.Accounts.term_schema()},
        "recent_events" => %{"type" => "array", "items" => Atlas.MCP.Serializers.Accounts.event_schema()},
        "service_levels" => %{"type" => "array", "items" => Atlas.MCP.Serializers.Accounts.service_level_schema()},
        "service_level_extraction_checks" => %{
          "type" => "array",
          "items" => Atlas.MCP.Serializers.Accounts.service_level_extraction_check_schema()
        }
      },
      "required" => [
        "account",
        "contacts",
        "handles",
        "terms",
        "recent_events",
        "service_levels",
        "service_level_extraction_checks"
      ],
      "additionalProperties" => false
    }

  alias Atlas.Accounts.Query, as: AccountsQuery
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer

  @impl EMCP.Tool
  def description,
    do:
      "Get an account's full customer context, including legal name, address, billing, signatory, commercial terms, contacts, and recent events. Use this before preparing an order form or enterprise contract."

  @recent_event_limit 20

  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args) do
      account = AccountsQuery.get_account(account.id)

      {:ok,
       %{
         account: AccountSerializer.account(account),
         contacts: Enum.map(account.contacts, &AccountSerializer.contact/1),
         handles: Enum.map(account.account_handles, &AccountSerializer.handle/1),
         terms: Enum.map(account.terms, &AccountSerializer.term/1),
         recent_events: account.events |> Enum.take(@recent_event_limit) |> Enum.map(&AccountSerializer.event/1),
         service_levels: Enum.map(account.service_levels, &AccountSerializer.service_level/1),
         service_level_extraction_checks:
           account.service_level_extraction_checks
           |> Enum.take(5)
           |> Enum.map(&AccountSerializer.service_level_extraction_check/1)
       }}
    end
  end
end
