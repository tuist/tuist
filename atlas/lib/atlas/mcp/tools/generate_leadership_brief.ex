defmodule Atlas.MCP.Tools.GenerateLeadershipBrief do
  use Atlas.MCP.Tool,
    name: "generate_leadership_brief",
    schema: %{
      "type" => "object",
      "required" => ["cadence"],
      "properties" => %{"cadence" => %{"type" => "string", "enum" => ["weekly"]}}
    },
    output_schema: Atlas.MCP.Serializers.Briefs.brief_schema()

  alias Atlas.Briefs
  alias Atlas.MCP.Serializers.Briefs, as: BriefSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Generate the current weekly leadership financial pulse. Scheduled delivery runs every Monday."
  end

  def execute(conn, %{"cadence" => cadence}) do
    with :ok <- Tool.authorize_scope(conn, "briefs:write", "Leadership brief tools"),
         {:ok, brief} <- Briefs.generate_for_audience("leadership", cadence) do
      {:ok, BriefSerializer.brief(Briefs.get_brief(brief.id), include_items: true)}
    end
  end

  def execute(_conn, _args), do: {:error, "cadence is required."}
end
