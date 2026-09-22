defmodule Atlas.MCP.Tools.ListAccountAttentionSuggestions do
  @moduledoc "Lists account follow-up suggestions and their resolution history."

  use Atlas.MCP.Tool,
    name: "list_account_attention_suggestions",
    schema: %{
      "type" => "object",
      "properties" =>
        Map.put(Atlas.MCP.AccountLookup.identifier_schema_properties(), "status", %{
          "type" => "string",
          "enum" => ["pending", "actioned", "snoozed", "dismissed"]
        })
    },
    output_schema:
      Atlas.MCP.Serializers.Accounts.list_response_schema(
        :suggestions,
        Atlas.MCP.Serializers.Accounts.account_attention_suggestion_schema()
      )

  alias Atlas.Accounts
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer

  @impl EMCP.Tool
  def description, do: "List the account follow-up agent's pending and resolved suggestions."

  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args) do
      statuses = if is_binary(args["status"]), do: [args["status"]]

      suggestions =
        account
        |> Accounts.list_account_attention_suggestions(statuses: statuses)
        |> Enum.map(&AccountSerializer.account_attention_suggestion/1)

      {:ok, AccountSerializer.list_response(:suggestions, suggestions)}
    end
  end
end
