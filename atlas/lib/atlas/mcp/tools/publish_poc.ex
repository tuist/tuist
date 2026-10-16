defmodule Atlas.MCP.Tools.PublishPOC do
  @moduledoc "Publishes a POC by minting a public token if none exists."

  use Atlas.MCP.Tool,
    name: "publish_poc",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{"type" => "string"},
        "rotate" => %{"type" => "boolean", "description" => "Force a new token even if published."}
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
  def description, do: "Publish a POC or rotate its public token. Authenticated operators only."

  def execute(conn, %{"id" => id} = args) do
    user = Tool.current_user(conn)
    rotate? = Map.get(args, "rotate", false)

    case POCs.get_poc(id) do
      nil ->
        {:error, "POC not found."}

      poc ->
        result = if rotate?, do: POCs.rotate_public_token(poc, user), else: POCs.publish_poc(poc, user)

        case result do
          {:ok, poc} -> {:ok, %{"poc" => POCSerializers.poc(POCs.get_poc!(poc.id))}}
          {:error, :unauthorized} -> {:error, "Only authenticated operators can publish POCs."}
          {:error, changeset} -> {:error, "Could not publish POC: #{Tool.format_changeset_errors(changeset)}"}
        end
    end
  end
end
