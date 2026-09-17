defmodule Atlas.MCP.Tools.ListAccountLetters do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "list_account_letters",
    schema: %{
      "type" => "object",
      "properties" =>
        Map.put(Atlas.MCP.AccountLookup.identifier_schema_properties(), "limit", %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 100
        })
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "letters" => %{"type" => "array", "items" => Atlas.MCP.Serializers.Letters.letter_schema()}
      },
      "required" => ["letters"],
      "additionalProperties" => false
    }

  alias Atlas.Letters
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.Letters, as: LetterSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "List the stored postal letters for an account."

  def execute(conn, args) do
    with :ok <- Tool.authorize_executive(conn, "Letter tools"),
         {:ok, account} <- AccountLookup.resolve(args) do
      limit = args["limit"] || 25
      letters = Letters.list_account_letters(account, limit: limit)
      {:ok, %{letters: Enum.map(letters, &LetterSerializer.letter/1)}}
    end
  end
end
