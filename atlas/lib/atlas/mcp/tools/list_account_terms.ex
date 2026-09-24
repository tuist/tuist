defmodule Atlas.MCP.Tools.ListAccountTerms do
  @moduledoc """
  Lists an account's contract terms, most recent first.
  """

  use Atlas.MCP.Tool,
    name: "list_account_terms",
    schema: %{
      "type" => "object",
      "description" => "Provide one of account_id, account_key, or handle.",
      "properties" =>
        %{"page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}}
        |> Map.merge(Atlas.MCP.AccountLookup.identifier_schema_properties())
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "account" => Atlas.MCP.Serializers.Accounts.related_account_schema(),
        "terms" => %{"type" => "array", "items" => Atlas.MCP.Serializers.Accounts.term_schema()},
        "count" => %{"type" => "integer"}
      },
      "required" => ["account", "terms", "count"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List an account's contract terms, most recent first. The first term is the latest; copy it and shift the dates to renew a contract."
  end

  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args) do
      terms =
        account
        |> Accounts.list_terms()
        |> Enum.take(Tool.page_size(args))
        |> Enum.map(&AccountSerializer.term/1)

      {:ok,
       %{
         account: AccountSerializer.related_account(account),
         terms: terms,
         count: length(terms)
       }}
    end
  end
end
