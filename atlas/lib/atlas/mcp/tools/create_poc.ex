defmodule Atlas.MCP.Tools.CreatePOC do
  @moduledoc "Creates a new proof-of-concept for an account."

  use Atlas.MCP.Tool,
    name: "create_poc",
    schema: %{
      "type" => "object",
      "required" => ["account_id", "title"],
      "properties" => %{
        "account_id" => %{"type" => "string", "description" => "Atlas account identifier."},
        "title" => %{"type" => "string", "description" => "Short customer-facing title."},
        "status" => %{
          "type" => "string",
          "enum" => Atlas.Accounts.POCs.POC.statuses(),
          "description" => "Defaults to draft."
        },
        "hosting" => %{
          "type" => "string",
          "enum" => Atlas.Accounts.POCs.POC.hosting_values(),
          "description" => "Hosting model being evaluated."
        },
        "starts_on" => %{"type" => "string", "description" => "ISO 8601 date."},
        "ends_on" => %{"type" => "string", "description" => "ISO 8601 date."},
        "summary" => %{"type" => "string"},
        "brand_accent_color" => %{"type" => "string", "description" => "Hex color like #1a2b3c."},
        "brand_logo_url" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"poc" => Atlas.MCP.Tools.POCSerializers.poc_schema()},
      "required" => ["poc"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts.POCs
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.POCSerializers

  @impl EMCP.Tool
  def description, do: "Create a POC attached to an account. Authenticated operators only."

  def execute(conn, args) do
    attrs =
      Map.take(args, [
        "account_id",
        "title",
        "status",
        "hosting",
        "starts_on",
        "ends_on",
        "summary",
        "brand_accent_color",
        "brand_logo_url"
      ])

    case POCs.create_poc(attrs, Tool.current_user(conn)) do
      {:ok, poc} -> {:ok, %{"poc" => POCSerializers.poc(poc)}}
      {:error, :unauthorized} -> {:error, "Only authenticated operators can create POCs."}
      {:error, changeset} -> {:error, "Could not create POC: #{Tool.format_changeset_errors(changeset)}"}
    end
  end
end
