defmodule Atlas.MCP.Tools.ListGTMResearchTopics do
  @moduledoc """
  Lists configured GTM outreach research topics and search queries.
  """

  use Atlas.MCP.Tool,
    name: "list_gtm_research_topics",
    schema: %{
      "type" => "object",
      "properties" => %{}
    },
    output_schema:
      Atlas.MCP.Serializers.GTM.list_response_schema(
        :gtm_research_topics,
        Atlas.MCP.Serializers.GTM.signal_query_schema()
      )

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "List GTM outreach research topics, including curated and changelog-derived search queries."

  def execute(_conn, _args) do
    case GTM.ensure_research_signal_queries() do
      {:ok, _queries} ->
        queries =
          GTM.list_signal_queries(enabled?: true)
          |> Enum.map(&GTMSerializer.signal_query/1)

        {:ok, GTMSerializer.list_response(:gtm_research_topics, queries)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Could not prepare GTM research topics: #{Tool.format_changeset_errors(changeset)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
