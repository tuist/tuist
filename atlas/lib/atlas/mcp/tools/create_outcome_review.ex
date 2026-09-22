defmodule Atlas.MCP.Tools.CreateOutcomeReview do
  @moduledoc "Records an evidence-based review of a customer outcome."

  use Atlas.MCP.Tool,
    name: "create_outcome_review",
    schema: %{
      "type" => "object",
      "required" => ["outcome_id", "health", "summary"],
      "properties" => %{
        "outcome_id" => %{"type" => "string"},
        "health" => %{"type" => "string", "enum" => ["unknown", "on_track", "at_risk", "off_track"]},
        "summary" => %{"type" => "string"},
        "evidence" => %{"type" => "array", "items" => %{"type" => "string"}},
        "recommendation" => %{"type" => "string"}
      }
    },
    output_schema: Atlas.MCP.Serializers.Accounts.outcome_review_schema()

  alias Atlas.Accounts
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Record outcome health, evidence, and the recommended next move."

  def execute(conn, %{"outcome_id" => id} = args) do
    case Accounts.get_outcome(id) do
      nil ->
        {:error, "Outcome not found: #{id}"}

      outcome ->
        attrs =
          args
          |> Map.take(["health", "summary", "recommendation"])
          |> Map.put("evidence", %{"items" => Map.get(args, "evidence", [])})

        case Accounts.create_outcome_review(outcome, attrs, Tool.current_user(conn)) do
          {:ok, review} -> {:ok, AccountSerializer.outcome_review(review)}
          {:error, changeset} -> {:error, Tool.format_changeset_errors(changeset)}
        end
    end
  end

  def execute(_conn, _args), do: {:error, "outcome_id, health, and summary are required."}
end
