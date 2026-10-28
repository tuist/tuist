defmodule Atlas.MCP.Tools.ListAccountFeatureInterests do
  @moduledoc "Lists feature interests recorded for one account."

  use Atlas.MCP.Tool,
    name: "list_account_feature_interests",
    schema: %{
      "type" => "object",
      "properties" => Atlas.MCP.AccountLookup.identifier_schema_properties()
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "feature_interests" => %{
          "type" => "array",
          "items" => Atlas.MCP.Serializers.FeatureInterests.account_interest_schema()
        },
        "count" => %{"type" => "integer"}
      },
      "required" => ["feature_interests", "count"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.FeatureInterests

  @impl EMCP.Tool
  def description, do: "List each feature interest recorded from an account's timeline events."

  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args) do
      feature_interests =
        account
        |> Accounts.list_feature_interests_for_account()
        |> Enum.map(&List.first(&1.accounts))
        |> Enum.map(&FeatureInterests.account_interest/1)

      {:ok, %{feature_interests: feature_interests, count: length(feature_interests)}}
    end
  end
end
