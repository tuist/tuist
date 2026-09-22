defmodule Atlas.MCP.Tools.PostmortemSerializers do
  @moduledoc """
  Shared JSON serialization helpers for the postmortem MCP tools.
  """

  alias Atlas.Engineering.Postmortems, as: PostmortemContext
  alias Atlas.Engineering.Postmortems.ActionItem
  alias Atlas.Engineering.Postmortems.Postmortem
  alias Atlas.MCP.Tool

  def postmortem(%Postmortem{} = postmortem) do
    %{
      "id" => postmortem.id,
      "number" => postmortem.number,
      "title" => PostmortemContext.title(postmortem),
      "body" => postmortem.body,
      "share_token" => postmortem.share_token,
      "author" => author(postmortem),
      "domains" => domains(postmortem),
      "action_items" => action_items(postmortem),
      "inserted_at" => Tool.iso8601(postmortem.inserted_at),
      "updated_at" => Tool.iso8601(postmortem.updated_at),
      "path" => "/engineering/postmortems/#{postmortem.number}"
    }
  end

  def action_item(%ActionItem{} = action_item) do
    %{
      "id" => action_item.id,
      "postmortem_id" => action_item.postmortem_id,
      "title" => action_item.title,
      "description" => action_item.description,
      "resolution_url" => action_item.resolution_url,
      "priority" => Atom.to_string(action_item.priority),
      "completed" => not is_nil(action_item.completed_at),
      "completed_at" => action_item.completed_at && Tool.iso8601(action_item.completed_at),
      "inserted_at" => Tool.iso8601(action_item.inserted_at),
      "updated_at" => Tool.iso8601(action_item.updated_at)
    }
  end

  def action_items(%Postmortem{} = postmortem) do
    Enum.map(
      (Ecto.assoc_loaded?(postmortem.action_items) && postmortem.action_items) || [],
      &action_item/1
    )
  end

  defp author(%{created_by_user: user}) do
    if Ecto.assoc_loaded?(user) and not is_nil(user) do
      %{"id" => user.id, "email" => user.email, "name" => user.name}
    end
  end

  defp domains(%{domains: domains}) do
    Enum.map((Ecto.assoc_loaded?(domains) && domains) || [], fn domain ->
      %{"id" => domain.id, "name" => domain.name}
    end)
  end

  @doc "JSON schema fragment for a postmortem returned by MCP tools."
  def postmortem_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "number" => %{"type" => "integer"},
        "title" => %{"type" => "string"},
        "body" => %{"type" => "string"},
        "share_token" => %{"type" => ["string", "null"]},
        "author" => %{"type" => ["object", "null"]},
        "domains" => %{"type" => "array", "items" => %{"type" => "object"}},
        "action_items" => %{"type" => "array", "items" => action_item_schema()},
        "inserted_at" => %{"type" => ["string", "null"]},
        "updated_at" => %{"type" => ["string", "null"]},
        "path" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "number",
        "title",
        "body",
        "share_token",
        "author",
        "domains",
        "action_items",
        "inserted_at",
        "updated_at",
        "path"
      ],
      "additionalProperties" => false
    }
  end

  @doc "JSON schema fragment for a postmortem action item returned by MCP tools."
  def action_item_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "postmortem_id" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "description" => %{"type" => ["string", "null"]},
        "resolution_url" => %{"type" => ["string", "null"]},
        "priority" => %{"type" => "string"},
        "completed" => %{"type" => "boolean"},
        "completed_at" => %{"type" => ["string", "null"]},
        "inserted_at" => %{"type" => ["string", "null"]},
        "updated_at" => %{"type" => ["string", "null"]}
      },
      "required" => [
        "id",
        "postmortem_id",
        "title",
        "description",
        "resolution_url",
        "priority",
        "completed",
        "completed_at",
        "inserted_at",
        "updated_at"
      ],
      "additionalProperties" => false
    }
  end
end
