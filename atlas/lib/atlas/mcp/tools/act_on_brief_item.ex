defmodule Atlas.MCP.Tools.ActOnBriefItem do
  use Atlas.MCP.Tool,
    name: "act_on_brief_item",
    schema: %{
      "type" => "object",
      "required" => ["brief_item_id", "action"],
      "properties" => %{
        "brief_item_id" => %{"type" => "string"},
        "action" => %{
          "type" => "string",
          "enum" => ["claim", "acknowledge", "complete", "dismiss", "rate_useful", "rate_not_useful", "suppress"]
        },
        "note" => %{"type" => "string"},
        "suppression_days" => %{"type" => "integer", "minimum" => 1, "maximum" => 365}
      }
    },
    output_schema: Atlas.MCP.Serializers.Briefs.brief_item_schema()

  alias Atlas.Briefs.ItemActions
  alias Atlas.MCP.Serializers.Briefs, as: BriefSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Claim, acknowledge, resolve, rate, or suppress a leadership brief item while preserving its audit trail."
  end

  def execute(conn, %{"brief_item_id" => id, "action" => action} = args) do
    with :ok <- Tool.authorize_scope(conn, "briefs:write", "Leadership brief tools"),
         {:ok, item} <- perform(action, id, args, Tool.current_user(conn)) do
      {:ok, BriefSerializer.brief_item(item, include_evidence: true)}
    end
  end

  def execute(_conn, _args), do: {:error, "brief_item_id and action are required."}

  defp perform("claim", id, _args, actor), do: ItemActions.claim(id, actor, interface: "mcp")

  defp perform("acknowledge", id, _args, actor), do: ItemActions.acknowledge(id, actor, interface: "mcp")

  defp perform("complete", id, args, actor), do: ItemActions.complete(id, args["note"], actor, interface: "mcp")

  defp perform("dismiss", id, args, actor), do: ItemActions.dismiss(id, args["note"], actor, interface: "mcp")

  defp perform("rate_useful", id, args, actor),
    do: ItemActions.rate(id, "useful", args["note"] || "Rated useful through MCP", actor, interface: "mcp")

  defp perform("rate_not_useful", id, args, actor),
    do: ItemActions.rate(id, "not_useful", args["note"] || "Rated not useful through MCP", actor, interface: "mcp")

  defp perform("suppress", id, args, actor),
    do:
      ItemActions.suppress(id, args["note"] || "Suppressed through MCP", args["suppression_days"] || 30, actor,
        interface: "mcp"
      )

  defp perform(_action, _id, _args, _actor), do: {:error, "Unsupported brief action."}
end
