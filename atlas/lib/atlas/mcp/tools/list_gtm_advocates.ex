defmodule Atlas.MCP.Tools.ListGTMAdvocates do
  @moduledoc """
  Lists public Tuist advocates discovered from GTM outreach signals.
  """

  use Atlas.MCP.Tool,
    name: "list_gtm_advocates",
    schema: %{
      "type" => "object",
      "properties" => %{
        "status" => %{
          "type" => "string",
          "enum" => ["new", "reviewed", "qualified", "rejected", "converted"]
        },
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema:
      Atlas.MCP.Serializers.GTM.list_response_schema(
        :gtm_advocates,
        Atlas.MCP.Serializers.GTM.advocate_schema()
      )

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "List public Tuist advocates and the companies/opportunities they are connected to."

  def execute(_conn, args) do
    advocates =
      [status: args["status"], limit: Tool.page_size(args)]
      |> GTM.list_gtm_advocates()
      |> Enum.map(&GTMSerializer.advocate/1)

    {:ok, GTMSerializer.list_response(:gtm_advocates, advocates)}
  end
end
