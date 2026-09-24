defmodule Atlas.MCP.Tools.ListAccountEvents do
  @moduledoc """
  Lists timeline events for an account (emails, meetings, notes, Slack
  messages), most recent first.
  """

  use Atlas.MCP.Tool,
    name: "list_account_events",
    schema: %{
      "type" => "object",
      "properties" =>
        Map.merge(Atlas.MCP.AccountLookup.identifier_schema_properties(), %{
          "kind" => %{
            "type" => "string",
            "description" => ~s{Filter to a specific event kind (e.g. "email", "meeting", "note").}
          },
          "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
        })
    },
    output_schema:
      Atlas.MCP.Serializers.Accounts.list_response_schema(:events, Atlas.MCP.Serializers.Accounts.event_schema())

  import Ecto.Query

  alias Atlas.Accounts.Event
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Repo

  @impl EMCP.Tool
  def description, do: "List timeline events for an account, most recent first."

  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args) do
      limit = Tool.page_size(args)

      events =
        Event
        |> where([e], e.account_id == ^account.id)
        |> maybe_filter_kind(args)
        |> order_by([e], desc: e.occurred_at, desc: e.inserted_at)
        |> limit(^limit)
        |> preload(:author)
        |> Repo.all()
        |> Enum.map(&AccountSerializer.event/1)

      {:ok, AccountSerializer.list_response(:events, events)}
    end
  end

  defp maybe_filter_kind(query, %{"kind" => kind}) when is_binary(kind) and kind != "" do
    where(query, [e], e.kind == ^kind)
  end

  defp maybe_filter_kind(query, _), do: query
end
