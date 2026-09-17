defmodule Atlas.MCP.Tools.UpdateFeatureInterestAccountContext do
  @moduledoc "Updates internal context for an account's feature interest."

  use Atlas.MCP.Tool,
    name: "update_feature_interest_account_context",
    schema: %{
      "type" => "object",
      "required" => ["feature_interest_account_id", "context"],
      "properties" => %{
        "feature_interest_account_id" => %{"type" => "string"},
        "context" => %{"type" => "string"}
      }
    },
    output_schema: Atlas.MCP.Serializers.FeatureInterests.account_interest_schema()

  alias Atlas.Accounts
  alias Atlas.MCP.Serializers.FeatureInterests
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Update the internal context for one account's recorded feature interest."

  def execute(conn, %{"feature_interest_account_id" => id, "context" => context}) do
    with :ok <- Tool.authorize_executive(conn, "Feature interest tools"),
         interest_account when not is_nil(interest_account) <- Accounts.get_feature_interest_account(id) do
      case Accounts.update_feature_interest_notes(interest_account, %{"notes" => context}, Tool.current_user(conn)) do
        {:ok, updated} ->
          {:ok,
           updated.id
           |> Accounts.get_feature_interest_account()
           |> FeatureInterests.account_interest()}

        {:error, changeset} ->
          {:error, Tool.format_changeset_errors(changeset)}
      end
    else
      nil -> {:error, "Feature interest record not found: #{id}"}
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(_conn, _args), do: {:error, "feature_interest_account_id and context are required."}
end
