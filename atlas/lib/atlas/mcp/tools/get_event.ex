defmodule Atlas.MCP.Tools.GetEvent do
  @moduledoc """
  Returns the full content of a single event, including the body. Useful
  when drafting follow-ups based on the last email or meeting transcript.
  """

  use Atlas.MCP.Tool,
    name: "get_event",
    schema: %{
      "type" => "object",
      "required" => ["event_id"],
      "properties" => %{
        "event_id" => %{"type" => "string", "description" => "UUID of the event."}
      }
    },
    output_schema: Atlas.MCP.Serializers.Accounts.full_event_schema()

  alias Atlas.Accounts.Event
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.Repo

  @impl EMCP.Tool
  def description, do: "Get the full body and metadata for a single account event."

  def execute(_conn, %{"event_id" => id}) when is_binary(id) do
    Event
    |> Repo.get(id)
    |> Repo.preload(:author)
    |> case do
      nil ->
        {:error, "Event not found: #{id}"}

      event ->
        {:ok, AccountSerializer.full_event(event)}
    end
  end

  def execute(_conn, _args), do: {:error, "event_id is required."}
end
