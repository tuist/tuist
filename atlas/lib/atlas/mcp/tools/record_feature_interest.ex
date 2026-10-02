defmodule Atlas.MCP.Tools.RecordFeatureInterest do
  @moduledoc "Records a feature interest from an account timeline event."

  use Atlas.MCP.Tool,
    name: "record_feature_interest",
    schema: %{
      "type" => "object",
      "required" => ["account_event_id", "title", "summary"],
      "properties" =>
        Map.merge(Atlas.MCP.AccountLookup.identifier_schema_properties(), %{
          "account_event_id" => %{"type" => "string"},
          "title" => %{"type" => "string"},
          "summary" => %{"type" => "string"},
          "context" => %{"type" => "string"}
        })
    },
    output_schema: Atlas.MCP.Serializers.FeatureInterests.feature_interest_schema()

  alias Atlas.Accounts
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.FeatureInterests
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Record an account's product interest from a specific timeline event, such as a meeting transcript or customer conversation."
  end

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "accounts:write", "Feature interest tools"),
         {:ok, account} <- AccountLookup.resolve(args),
         {:ok, event} <- Accounts.get_account_event(account, args["account_event_id"]) do
      case Accounts.record_feature_interest_from_event(event, interest_attrs(args), Tool.current_user(conn)) do
        {:ok, %{interest: interest}} -> {:ok, FeatureInterests.feature_interest(interest)}
        {:error, :account_required} -> {:error, "Timeline event must be linked to an account"}
        {:error, changeset} -> {:error, Tool.format_changeset_errors(changeset)}
      end
    else
      {:error, :event_not_found} -> {:error, "Timeline event is not linked to the specified account"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp interest_attrs(args) do
    args
    |> Map.take(["title", "summary"])
    |> Map.put("notes", args["context"])
  end
end
