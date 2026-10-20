defmodule Atlas.MCP.Tools.RemovePOCScopeFeature do
  @moduledoc "Removes a feature interest from a POC's scope."

  use Atlas.MCP.Tool,
    name: "remove_poc_scope_feature",
    schema: %{
      "type" => "object",
      "required" => ["poc_id", "feature_interest_id"],
      "properties" => %{
        "poc_id" => %{"type" => "string"},
        "feature_interest_id" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"poc" => Atlas.MCP.Tools.POCSerializers.poc_schema()},
      "required" => ["poc"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts.POCs
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.POCSerializers

  @impl EMCP.Tool
  def description, do: "Remove a feature interest from a POC's scope. Authenticated operators only."

  def execute(conn, %{"poc_id" => poc_id, "feature_interest_id" => feature_interest_id}) do
    user = Tool.current_user(conn)

    case POCs.get_poc(poc_id) do
      nil ->
        {:error, "POC not found."}

      poc ->
        case POCs.remove_scope_feature(poc, feature_interest_id, user) do
          {:ok, _} -> {:ok, %{"poc" => POCSerializers.poc(POCs.get_poc!(poc.id))}}
          {:error, :not_found} -> {:error, "Scope feature not found on this POC."}
          {:error, :unauthorized} -> {:error, "Only authenticated operators can update POC scope."}
        end
    end
  end
end
