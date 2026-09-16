defmodule Atlas.MCP.Tools.EnrichGTMOpportunityContacts do
  @moduledoc """
  Finds suggested leaders for a GTM opportunity through Apollo.
  """

  use Atlas.MCP.Tool,
    name: "enrich_gtm_opportunity_contacts",
    schema: %{
      "type" => "object",
      "required" => ["opportunity_id"],
      "properties" => %{
        "opportunity_id" => %{"type" => "string"}
      }
    },
    output_schema:
      Atlas.MCP.Serializers.GTM.list_response_schema(
        :contacts,
        Atlas.MCP.Serializers.GTM.opportunity_contact_schema()
      )

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer

  @impl EMCP.Tool
  def description, do: "Use Apollo to find suggested engineering leaders for a GTM opportunity."

  def execute(_conn, %{"opportunity_id" => id}) do
    case GTM.enrich_gtm_opportunity_contacts(id) do
      {:ok, contacts} ->
        {:ok, GTMSerializer.list_response(:contacts, Enum.map(contacts, &GTMSerializer.opportunity_contact/1))}

      {:error, :not_found} ->
        {:error, "GTM opportunity not found."}

      {:error, :domain_required} ->
        {:error, "GTM opportunity needs a company domain or company name before Apollo enrichment."}

      {:error, :apollo_organization_not_found} ->
        {:error, "Apollo could not resolve the opportunity company."}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
