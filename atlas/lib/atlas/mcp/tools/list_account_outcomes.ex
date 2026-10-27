defmodule Atlas.MCP.Tools.ListAccountOutcomes do
  @moduledoc "Lists measurable outcomes for an account."

  use Atlas.MCP.Tool,
    name: "list_account_outcomes",
    schema: %{
      "type" => "object",
      "properties" =>
        Map.put(Atlas.MCP.AccountLookup.identifier_schema_properties(), "status", %{
          "type" => "string",
          "enum" => ["active", "achieved", "missed", "abandoned"]
        })
    },
    output_schema:
      Atlas.MCP.Serializers.Accounts.list_response_schema(
        :outcomes,
        Atlas.MCP.Serializers.Accounts.outcome_schema()
      )

  alias Atlas.Accounts
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer

  @impl EMCP.Tool
  def description, do: "List measurable outcomes and review history for an account."

  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args) do
      opts = if is_binary(args["status"]), do: [statuses: [args["status"]]], else: []
      outcomes = account |> Accounts.list_outcomes(opts) |> Enum.map(&AccountSerializer.outcome/1)
      {:ok, AccountSerializer.list_response(:outcomes, outcomes)}
    end
  end
end
