defmodule Atlas.MCP.Tools.NotifyGTMOpportunity do
  @moduledoc """
  Posts or refreshes the Slack notification for a GTM outreach opportunity.
  """

  use Atlas.MCP.Tool,
    name: "notify_gtm_opportunity",
    schema: %{
      "type" => "object",
      "required" => ["opportunity_id"],
      "properties" => %{
        "opportunity_id" => %{"type" => "string"},
        "force" => %{"type" => "boolean"}
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
  def description, do: "Post or refresh a Slack action thread for a high-score GTM opportunity."

  def execute(_conn, %{"opportunity_id" => id} = args) do
    case GTM.notify_gtm_opportunity(id, force?: args["force"] == true) do
      {:ok, opportunity} ->
        {:ok, %{gtm_opportunity: GTMSerializer.opportunity(opportunity)}}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Could not update GTM opportunity: #{Tool.format_changeset_errors(changeset)}"}

      {:error, reason} ->
        {:error, error_message(reason)}
    end
  end

  defp error_message(:not_found), do: "GTM opportunity not found."
  defp error_message(:score_below_threshold), do: "GTM opportunity score is below the Slack notification threshold."
  defp error_message(:gtm_outreach_slack_channel_not_configured), do: "GTM outreach Slack channel is not configured."
  defp error_message(reason), do: inspect(reason)
end
