defmodule Atlas.MCP.Tools.GenerateAccountAttentionSuggestions do
  @moduledoc "Generates evidence-backed account follow-up suggestions."

  use Atlas.MCP.Tool,
    name: "generate_account_attention_suggestions",
    schema: %{
      "type" => "object",
      "properties" => Atlas.MCP.AccountLookup.identifier_schema_properties()
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
  def description, do: "Analyze account usage and relationship evidence to suggest the next follow-up."

  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args),
         {:ok, suggestions} <- Accounts.generate_account_attention_suggestions(account.id) do
      suggestions = Enum.map(suggestions, &AccountSerializer.account_attention_suggestion/1)
      {:ok, AccountSerializer.list_response(:suggestions, suggestions)}
    else
      {:error, reason} -> {:error, "Could not generate account attention suggestions: #{inspect(reason)}"}
    end
  end
end
