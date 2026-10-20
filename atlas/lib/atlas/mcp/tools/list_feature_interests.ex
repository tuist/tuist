defmodule Atlas.MCP.Tools.ListFeatureInterests do
  @moduledoc "Lists product capabilities customers have requested."

  use Atlas.MCP.Tool,
    name: "list_feature_interests",
    schema: %{"type" => "object", "properties" => %{}},
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "feature_interests" => %{
          "type" => "array",
          "items" => Atlas.MCP.Serializers.FeatureInterests.feature_interest_schema()
        },
        "count" => %{"type" => "integer"}
      },
      "required" => ["feature_interests", "count"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts
  alias Atlas.MCP.Serializers.FeatureInterests
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "List requested product capabilities, ranked by the number of interested accounts."

  def execute(conn, _args) do
    with :ok <- Tool.authorize_scope(conn, "accounts:read", "Feature interest tools") do
      interests = Accounts.list_feature_interests() |> Enum.map(&FeatureInterests.feature_interest/1)
      {:ok, %{feature_interests: interests, count: length(interests)}}
    end
  end
end
