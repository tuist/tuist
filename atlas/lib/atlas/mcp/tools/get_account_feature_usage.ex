defmodule Atlas.MCP.Tools.GetAccountFeatureUsage do
  @moduledoc """
  Returns the latest Tuist feature-usage and integration snapshots for an account.
  """

  use Atlas.MCP.Tool,
    name: "get_account_feature_usage",
    schema: %{
      "type" => "object",
      "description" => "Provide one of account_id, account_key, or handle.",
      "properties" => Atlas.MCP.AccountLookup.identifier_schema_properties()
    },
    output_schema: %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["account_id", "account_name", "features"],
      "properties" => %{
        "account_id" => %{"type" => "string"},
        "account_name" => %{"type" => ["string", "null"]},
        "features" => %{
          "type" => "array",
          "items" => Atlas.MCP.Serializers.FeatureUsage.snapshot_schema()
        }
      }
    }

  alias Atlas.FeatureUsage
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.FeatureUsage, as: FeatureUsageSerializer

  @impl EMCP.Tool
  def description do
    "Get an account's latest Tuist feature-usage and integration snapshots: which features are active, " <>
      "when each was last used, and event counts over the last 24h / 7d / prior 7d. This includes " <>
      "single sign-on configuration and detected continuous-integration providers."
  end

  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args) do
      features =
        account.id
        |> FeatureUsage.latest_usage_for_account()
        |> Enum.map(&FeatureUsageSerializer.snapshot/1)

      {:ok, %{"account_id" => account.id, "account_name" => account.name, "features" => features}}
    end
  end
end
