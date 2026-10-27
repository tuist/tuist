defmodule Atlas.MCP.Tools.UpdatePOC do
  @moduledoc "Updates an existing POC."

  use Atlas.MCP.Tool,
    name: "update_poc",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "status" => %{"type" => "string", "enum" => Atlas.Accounts.POCs.POC.statuses()},
        "hosting" => %{"type" => "string", "enum" => Atlas.Accounts.POCs.POC.hosting_values()},
        "starts_on" => %{"type" => "string"},
        "ends_on" => %{"type" => "string"},
        "summary" => %{"type" => "string"},
        "brand_accent_color" => %{"type" => "string"},
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
  def description, do: "Update POC fields. Authenticated operators only."

  def execute(conn, %{"id" => id} = args) do
    user = Tool.current_user(conn)

    case POCs.get_poc(id) do
      nil ->
        {:error, "POC not found."}

      poc ->
        attrs =
          Map.take(args, [
            "title",
            "status",
            "hosting",
            "starts_on",
            "ends_on",
            "summary",
            "brand_accent_color",
            "brand_logo_url"
          ])

        case POCs.update_poc(poc, attrs, user) do
          {:ok, poc} -> {:ok, %{"poc" => POCSerializers.poc(poc)}}
          {:error, :unauthorized} -> {:error, "Only authenticated operators can update POCs."}
          {:error, changeset} -> {:error, "Could not update POC: #{Tool.format_changeset_errors(changeset)}"}
        end
    end
  end
end
