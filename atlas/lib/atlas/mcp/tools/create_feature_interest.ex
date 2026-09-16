defmodule Atlas.MCP.Tools.CreateFeatureInterest do
  @moduledoc "Creates a product capability in the feature-interest registry."

  use Atlas.MCP.Tool,
    name: "create_feature_interest",
    schema: %{
      "type" => "object",
      "required" => ["title"],
      "properties" => %{
        "title" => %{"type" => "string"},
        "status" => %{"type" => "string", "enum" => Atlas.Accounts.FeatureInterest.statuses()}
      }
    },
    output_schema: Atlas.MCP.Serializers.FeatureInterests.feature_interest_schema()

  alias Atlas.Accounts
  alias Atlas.MCP.Serializers.FeatureInterests
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Create a capability in the feature-interest registry before accounts have requested it."

  def execute(conn, args) do
    with :ok <- Tool.authorize_executive(conn, "Feature interest tools") do
      case Accounts.create_feature_interest(args, Tool.current_user(conn)) do
        {:ok, interest} -> {:ok, FeatureInterests.feature_interest(interest)}
        {:error, changeset} -> {:error, "Could not create feature interest: #{Tool.format_changeset_errors(changeset)}"}
      end
    end
  end
end
