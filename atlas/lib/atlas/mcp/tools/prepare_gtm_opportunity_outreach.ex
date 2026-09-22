defmodule Atlas.MCP.Tools.PrepareGTMOpportunityOutreach do
  @moduledoc """
  Enriches a GTM opportunity with Apollo leaders and posts or refreshes Slack.
  """

  use Atlas.MCP.Tool,
    name: "prepare_gtm_opportunity_outreach",
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
      "properties" => %{
        "gtm_opportunity" => Atlas.MCP.Serializers.GTM.opportunity_schema(),
        "contacts" => %{
          "type" => "array",
          "items" => Atlas.MCP.Serializers.GTM.opportunity_contact_schema()
        },
        "contact_error" => %{"type" => ["string", "null"]}
      },
      "required" => ["gtm_opportunity", "contacts", "contact_error"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Use Apollo to find leaders for a GTM opportunity, then post or refresh its Slack action thread."

  def execute(_conn, %{"opportunity_id" => id} = args) do
    case GTM.prepare_gtm_opportunity_for_outreach(id, force?: args["force"] == true) do
      {:ok, result} ->
        {:ok,
         %{
           gtm_opportunity: GTMSerializer.opportunity(result.opportunity),
           contacts: Enum.map(result.contacts, &GTMSerializer.opportunity_contact/1),
           contact_error: error_message(result.contact_error)
         }}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Could not update GTM opportunity: #{Tool.format_changeset_errors(changeset)}"}

      {:error, reason} ->
        {:error, error_message(reason)}
    end
  end

  defp error_message(nil), do: nil
  defp error_message(:not_found), do: "GTM opportunity not found."
  defp error_message(:score_below_threshold), do: "GTM opportunity score is below the Slack notification threshold."
  defp error_message(:apollo_api_key_not_configured), do: "Apollo is not configured."
  defp error_message(:apollo_organization_not_found), do: "Apollo could not resolve that company."
  defp error_message(:gtm_outreach_slack_channel_not_configured), do: "GTM outreach Slack channel is not configured."
  defp error_message(reason), do: inspect(reason)
end
