defmodule Atlas.MCP.Tools.CreateAccountNote do
  @moduledoc """
  Appends a free-form note event to an account's timeline, attributed
  to the authenticated user.
  """

  use Atlas.MCP.Tool,
    name: "create_account_note",
    schema: %{
      "type" => "object",
      "required" => ["body"],
      "properties" =>
        Map.merge(Atlas.MCP.AccountLookup.identifier_schema_properties(), %{
          "body" => %{"type" => "string", "description" => "Note body (markdown ok)."},
          "title" => %{"type" => "string"}
        })
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "event" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "string"},
            "kind" => %{"type" => ["string", "null"]},
            "title" => %{"type" => ["string", "null"]},
            "body" => %{"type" => ["string", "null"]},
            "occurred_at" => %{"type" => ["string", "null"]}
          },
          "required" => ["id", "kind", "title", "body", "occurred_at"],
          "additionalProperties" => false
        }
      },
      "required" => ["event"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Append a note to an account's timeline."

  def execute(conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args) do
      attrs = Map.take(args, ["body", "title"])

      case Accounts.create_note(account, attrs, Tool.current_user(conn)) do
        {:ok, event} ->
          {:ok,
           %{
             event: %{
               id: event.id,
               kind: event.kind,
               title: event.title,
               body: event.body,
               occurred_at: Tool.iso8601(event.occurred_at)
             }
           }}

        {:error, changeset} ->
          {:error, "Could not create note: #{Tool.format_changeset_errors(changeset)}"}
      end
    end
  end
end
