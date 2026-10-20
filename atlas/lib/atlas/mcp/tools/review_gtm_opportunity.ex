defmodule Atlas.MCP.Tools.ReviewGTMOpportunity do
  @moduledoc """
  Updates the review status of a GTM outreach opportunity.
  """

  use Atlas.MCP.Tool,
    name: "review_gtm_opportunity",
    schema: %{
      "type" => "object",
      "required" => ["opportunity_id", "status"],
      "properties" => %{
        "opportunity_id" => %{"type" => "string"},
        "status" => %{
          "type" => "string",
          "enum" => ["new", "reviewed", "qualified", "rejected"]
        },
        "rejected_reason" => %{"type" => "string"}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"gtm_opportunity" => Atlas.MCP.Serializers.GTM.opportunity_schema()},
      "required" => ["gtm_opportunity"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Mark a GTM opportunity as new, reviewed, qualified, or rejected."

  def execute(_conn, %{"opportunity_id" => id, "status" => status} = args) do
    case GTM.update_gtm_opportunity_status(id, status, review_attrs(args)) do
      {:ok, opportunity} ->
        {:ok, %{gtm_opportunity: GTMSerializer.opportunity(opportunity)}}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Could not update GTM opportunity: #{Tool.format_changeset_errors(changeset)}"}

      {:error, :not_found} ->
        {:error, "GTM opportunity not found."}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp review_attrs(%{"rejected_reason" => rejected_reason}) when is_binary(rejected_reason) do
    %{rejected_reason: rejected_reason}
  end

  defp review_attrs(_args), do: %{}
end
