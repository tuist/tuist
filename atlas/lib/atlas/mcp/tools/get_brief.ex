defmodule Atlas.MCP.Tools.GetBrief do
  use Atlas.MCP.Tool,
    name: "get_brief",
    schema: %{
      "type" => "object",
      "required" => ["brief_id"],
      "properties" => %{"brief_id" => %{"type" => "string"}}
    },
    output_schema: Atlas.MCP.Serializers.Briefs.brief_schema()

  alias Atlas.Briefs
  alias Atlas.MCP.Serializers.Briefs, as: BriefSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Get one leadership brief with its next moves, evidence, owners, results, and feedback."

  def execute(conn, %{"brief_id" => id}) do
    with :ok <- Tool.authorize_executive(conn, "Leadership brief tools"),
         brief when not is_nil(brief) <- Briefs.get_brief(id) do
      {:ok, BriefSerializer.brief(brief, include_items: true)}
    else
      nil -> {:error, "Brief not found: #{id}"}
      {:error, _message} = error -> error
    end
  end

  def execute(_conn, _args), do: {:error, "brief_id is required."}
end
