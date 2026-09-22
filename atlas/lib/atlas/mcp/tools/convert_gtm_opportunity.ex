defmodule Atlas.MCP.Tools.ConvertGTMOpportunity do
  @moduledoc """
  Converts a qualified GTM outreach opportunity into an Atlas prospect account.
  """

  use Atlas.MCP.Tool,
    name: "convert_gtm_opportunity",
    schema: %{
      "type" => "object",
      "required" => ["opportunity_id"],
      "properties" => %{
        "opportunity_id" => %{"type" => "string"}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "account" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "string"},
            "account_key" => %{"type" => ["string", "null"]},
            "name" => %{"type" => ["string", "null"]},
            "primary_domain" => %{"type" => ["string", "null"]},
            "segment" => %{"type" => ["string", "null"]},
            "url" => %{"type" => ["string", "null"]}
          },
          "required" => ["id", "account_key", "name", "primary_domain", "segment", "url"],
          "additionalProperties" => false
        },
        "gtm_opportunity" => Atlas.MCP.Serializers.GTM.opportunity_schema()
      },
      "required" => ["account", "gtm_opportunity"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Convert a GTM outreach opportunity into a prospect account."

  def execute(_conn, %{"opportunity_id" => id}) do
    case GTM.convert_gtm_opportunity(id) do
      {:ok, account, opportunity} ->
        {:ok,
         %{
           account: %{
             id: account.id,
             account_key: account.account_key,
             name: account.name,
             primary_domain: account.primary_domain,
             segment: account.segment,
             url: Tool.account_url(account.id)
           },
           gtm_opportunity: GTMSerializer.opportunity(opportunity)
         }}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Could not convert GTM opportunity: #{Tool.format_changeset_errors(changeset)}"}

      {:error, :not_found} ->
        {:error, "GTM opportunity not found."}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
