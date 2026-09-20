defmodule Atlas.MCP.Tools.CreatePostmortem do
  @moduledoc "Publishes a postmortem."

  use Atlas.MCP.Tool,
    name: "create_postmortem",
    schema: %{
      "type" => "object",
      "required" => ["body"],
      "properties" => %{
        "body" => %{"type" => "string", "description" => "Complete postmortem in Markdown."},
        "domain_ids" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "description" => "Domain identifiers to associate with the postmortem."
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"postmortem" => Atlas.MCP.Tools.PostmortemSerializers.postmortem_schema()},
      "required" => ["postmortem"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Postmortems
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.PostmortemSerializers

  @impl EMCP.Tool
  def description, do: "Publish a postmortem. Authenticated operators only."

  def execute(conn, args) do
    attrs = Map.take(args, ["body", "domain_ids"])

    case Postmortems.publish_postmortem(attrs, Tool.current_user(conn)) do
      {:ok, postmortem} ->
        postmortem = Postmortems.get_postmortem!(postmortem.id)
        {:ok, %{"postmortem" => PostmortemSerializers.postmortem(postmortem)}}

      {:error, :unauthorized} ->
        {:error, "Only authenticated operators can publish postmortems."}

      {:error, changeset} ->
        {:error, "Could not publish postmortem: #{Tool.format_changeset_errors(changeset)}"}
    end
  end
end
