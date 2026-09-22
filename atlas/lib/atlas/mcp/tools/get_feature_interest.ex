defmodule Atlas.MCP.Tools.GetFeatureInterest do
  @moduledoc "Gets the accounts and conversation evidence for a product capability."

  use Atlas.MCP.Tool,
    name: "get_feature_interest",
    schema: %{
      "type" => "object",
      "required" => ["feature_interest_id"],
      "properties" => %{"feature_interest_id" => %{"type" => "string"}}
    },
    output_schema: Atlas.MCP.Serializers.FeatureInterests.feature_interest_detail_schema()

  alias Atlas.Accounts
  alias Atlas.MCP.Serializers.FeatureInterests
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Get every interested account and the source conversation for one requested capability."

  def execute(conn, %{"feature_interest_id" => id}) do
    with :ok <- Tool.authorize_scope(conn, "accounts:read", "Feature interest tools") do
      case Accounts.get_feature_interest(id) do
        nil -> {:error, "Feature interest not found"}
        interest -> {:ok, FeatureInterests.feature_interest_detail(interest)}
      end
    end
  end
end
