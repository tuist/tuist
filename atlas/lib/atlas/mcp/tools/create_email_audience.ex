defmodule Atlas.MCP.Tools.CreateEmailAudience do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "create_email_audience",
    schema: %{
      "type" => "object",
      "required" => ["name"],
      "properties" => %{
        "name" => %{"type" => "string"},
        "slug" => %{"type" => "string"},
        "description" => %{"type" => "string"},
        "membership_type" => %{"type" => "string", "enum" => ["static", "dynamic"]},
        "rules" => %{
          "type" => "object",
          "properties" => %{
            "account_segment" => %{"type" => "string", "enum" => ["customer", "lead", "prospect"]},
            "hosting" => %{"type" => "string", "enum" => ["all", "self_hosted"]},
            "recipient_source" => %{"type" => "string", "enum" => ["account_contacts", "incident_contacts"]},
            "contacts_per_account" => %{"type" => "string", "enum" => ["all", "one"]}
          }
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"audience" => Atlas.MCP.Serializers.GTMEmail.audience_schema()},
      "required" => ["audience"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTMEmail
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do:
      "Create an Atlas email audience. Static audiences use manual subscribers; dynamic audiences continuously resolve matching account contacts or security-incident contacts extracted from contracts. Dynamic account contacts can include all contacts or one deterministic contact per account. A URL-safe slug is derived when omitted."

  def execute(conn, args) do
    case GTM.create_email_audience(
           Map.take(args, ~w(name slug description membership_type rules)),
           Tool.current_user(conn)
         ) do
      {:ok, audience} -> {:ok, %{audience: GTMEmail.audience(audience)}}
      {:error, changeset} -> {:error, "Could not create audience: #{Tool.format_changeset_errors(changeset)}"}
    end
  end
end
